use std::sync::mpsc::{self, Sender};
use std::sync::Arc;
use std::thread::JoinHandle;

use rubato::{
    Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};

use super::engine::WhisperEngine;
use super::stream_tuning::tuning_for;
use crate::audio::{SileroVad, VAD_CHUNK_SIZE};

const TARGET_RATE: usize = 16_000;
const STREAM_VAD_THRESHOLD: f32 = 0.4;
const MIN_DECODE_SAMPLES: usize = 1600;

type TextSink = Box<dyn Fn(String) + Send>;

enum StreamMsg {
    Samples(Vec<f32>),
    Finalize,
    Cancel,
}

/// Cheap, cloneable handle the audio thread uses to push source-rate mono samples
/// into the streaming worker. Sending is non-blocking (unbounded channel).
#[derive(Clone)]
pub struct StreamFeeder {
    tx: Sender<StreamMsg>,
}

impl StreamFeeder {
    pub fn feed(&self, samples: &[f32]) {
        let _ = self.tx.send(StreamMsg::Samples(samples.to_vec()));
    }
}

/// Transcribes speech segments as they complete during a hold, so that on release
/// only the trailing segment remains to decode. Final text is the concatenation of
/// all segment decodes.
pub struct StreamingSession {
    sender: Sender<StreamMsg>,
    handle: Option<JoinHandle<()>>,
}

impl StreamingSession {
    pub fn start(
        engine: Arc<WhisperEngine>,
        source_rate: u32,
        language: Option<String>,
        on_final: TextSink,
        on_error: TextSink,
    ) -> Result<(Self, StreamFeeder), String> {
        let (tx, rx) = mpsc::channel::<StreamMsg>();

        let mut resampler = if source_rate as usize == TARGET_RATE {
            None
        } else {
            Some(StreamResampler::new(source_rate)?)
        };

        let handle = std::thread::Builder::new()
            .name("tt-stream".into())
            .spawn(move || {
                let tuning = tuning_for(engine.chip_family(), engine.tier_id());
                let endpoint_silence_chunks =
                    (tuning.endpoint_silence_ms as usize * TARGET_RATE / 1000 / VAD_CHUNK_SIZE).max(1);
                let min_segment_samples = tuning.min_segment_ms as usize * TARGET_RATE / 1000;
                let max_segment_samples = tuning.max_segment_ms as usize * TARGET_RATE / 1000;

                let mut vad = match SileroVad::new(STREAM_VAD_THRESHOLD) {
                    Ok(v) => v,
                    Err(e) => {
                        on_error(e);
                        return;
                    }
                };

                let mut buf16: Vec<f32> = Vec::with_capacity(TARGET_RATE * 30);
                let mut vad_cursor = 0usize; // chunk-aligned index processed by VAD
                let mut last_committed = 0usize; // index decoded into a segment
                let mut silence_chunks = 0usize;
                let mut speech_in_segment = false;
                let mut texts: Vec<String> = Vec::new();
                let lang = language.as_deref();

                while let Ok(msg) = rx.recv() {
                    match msg {
                        StreamMsg::Samples(s) => {
                            append_resampled(resampler.as_mut(), &s, &mut buf16);

                            while vad_cursor + VAD_CHUNK_SIZE <= buf16.len() {
                                let chunk = &buf16[vad_cursor..vad_cursor + VAD_CHUNK_SIZE];
                                let speech = vad.is_speech(chunk);
                                vad_cursor += VAD_CHUNK_SIZE;

                                if speech {
                                    silence_chunks = 0;
                                    speech_in_segment = true;
                                } else {
                                    silence_chunks += 1;
                                }

                                let seg_len = vad_cursor - last_committed;
                                let endpoint = speech_in_segment
                                    && silence_chunks >= endpoint_silence_chunks
                                    && seg_len >= min_segment_samples;
                                let hardcap = seg_len >= max_segment_samples;

                                if speech_in_segment && (endpoint || hardcap) {
                                    decode_segment(&engine, &buf16[last_committed..vad_cursor], lang, &mut texts);
                                    last_committed = vad_cursor;
                                    silence_chunks = 0;
                                    speech_in_segment = false;
                                } else if hardcap {
                                    // segment is pure silence — drop it
                                    last_committed = vad_cursor;
                                    silence_chunks = 0;
                                }

                                // Compact committed audio so memory stays bounded to one
                                // pending segment regardless of how long the key is held.
                                if last_committed > 0 {
                                    buf16.drain(..last_committed);
                                    vad_cursor -= last_committed;
                                    last_committed = 0;
                                }
                            }
                        }
                        StreamMsg::Finalize => {
                            // Drain any audio still queued (including a buffer the audio
                            // thread sent mid-stop) and flush the resampler's tail.
                            while let Ok(StreamMsg::Samples(s)) = rx.try_recv() {
                                append_resampled(resampler.as_mut(), &s, &mut buf16);
                            }
                            if let Some(rs) = resampler.as_mut() {
                                rs.flush(&mut buf16);
                            }
                            if last_committed < buf16.len() {
                                decode_segment(&engine, &buf16[last_committed..], lang, &mut texts);
                            }
                            let joined = texts.join(" ");
                            let normalized = joined.split_whitespace().collect::<Vec<_>>().join(" ");
                            #[cfg(debug_assertions)]
                            eprintln!("tt-stream finalize segments={} chars={}", texts.len(), normalized.len());
                            on_final(normalized);
                            break;
                        }
                        StreamMsg::Cancel => break,
                    }
                }
            })
            .map_err(|e| format!("spawn stream thread: {e}"))?;

        let feeder = StreamFeeder { tx: tx.clone() };
        Ok((Self { sender: tx, handle: Some(handle) }, feeder))
    }

    pub fn finalize(&self) {
        let _ = self.sender.send(StreamMsg::Finalize);
    }

    pub fn cancel(&self) {
        let _ = self.sender.send(StreamMsg::Cancel);
    }
}

impl Drop for StreamingSession {
    fn drop(&mut self) {
        let _ = self.sender.send(StreamMsg::Cancel);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

fn decode_segment(engine: &WhisperEngine, seg: &[f32], language: Option<&str>, texts: &mut Vec<String>) {
    if seg.len() < MIN_DECODE_SAMPLES {
        return;
    }
    match engine.transcribe(seg, language) {
        Ok(result) => {
            let trimmed = result.text.trim();
            if !trimmed.is_empty() {
                texts.push(trimmed.to_string());
            }
        }
        Err(_e) => {
            #[cfg(debug_assertions)]
            eprintln!("tt-stream segment error: {_e}");
        }
    }
}

fn append_resampled(resampler: Option<&mut StreamResampler>, input: &[f32], out: &mut Vec<f32>) {
    match resampler {
        Some(rs) => rs.push(input, out),
        None => out.extend_from_slice(input),
    }
}

/// Persistent resampler that converts arbitrary-sized source-rate blocks to 16 kHz,
/// buffering the remainder between calls (SincFixedIn needs a fixed input size).
struct StreamResampler {
    inner: SincFixedIn<f32>,
    chunk: usize,
    ratio: f64,
    pending: Vec<f32>,
}

impl StreamResampler {
    fn new(source_rate: u32) -> Result<Self, String> {
        let params = SincInterpolationParameters {
            sinc_len: 256,
            f_cutoff: 0.95,
            interpolation: SincInterpolationType::Linear,
            oversampling_factor: 256,
            window: WindowFunction::BlackmanHarris2,
        };
        let chunk = 1024;
        let ratio = TARGET_RATE as f64 / source_rate as f64;
        let inner = SincFixedIn::<f32>::new(ratio, 2.0, params, chunk, 1)
            .map_err(|e| format!("stream resampler init: {e}"))?;
        Ok(Self { inner, chunk, ratio, pending: Vec::with_capacity(chunk * 2) })
    }

    fn push(&mut self, input: &[f32], out: &mut Vec<f32>) {
        self.pending.extend_from_slice(input);
        while self.pending.len() >= self.chunk {
            let block: Vec<f32> = self.pending.drain(..self.chunk).collect();
            if let Ok(res) = self.inner.process(&[block], None) {
                out.extend_from_slice(&res[0]);
            }
        }
    }

    // Flushes the sub-chunk remainder so the trailing audio isn't lost on finalize.
    fn flush(&mut self, out: &mut Vec<f32>) {
        if self.pending.is_empty() {
            return;
        }
        let valid = self.pending.len();
        let mut block = std::mem::take(&mut self.pending);
        block.resize(self.chunk, 0.0);
        if let Ok(res) = self.inner.process(&[block], None) {
            let keep = ((valid as f64) * self.ratio).ceil() as usize;
            out.extend_from_slice(&res[0][..keep.min(res[0].len())]);
        }
    }
}
