use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use rubato::{
    Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};

const TARGET_SAMPLE_RATE: u32 = 16_000;
const LEVEL_EMIT_HZ: u32 = 30;
const RECORDING_BUFFER_CAPACITY: usize = 16_000 * 30;

type LevelFn = Box<dyn Fn(f32) + Send>;
type ChunkFn = Box<dyn Fn(Vec<f32>) + Send>;

struct PersistentStream {
    stream: cpal::Stream,
    source_sample_rate: u32,
}

// SAFETY: PersistentStream is only accessed through AudioRecorder.stream_state behind a Mutex.
// cpal::Stream is Send (the host owns the audio thread); Sync is enforced by the outer Mutex.
unsafe impl Send for PersistentStream {}
unsafe impl Sync for PersistentStream {}

pub struct AudioRecorder {
    recording: Arc<AtomicBool>,
    buffer: Arc<Mutex<Vec<f32>>>,
    stream_state: Mutex<Option<PersistentStream>>,
    level_sink: Arc<Mutex<Option<LevelFn>>>,
    // Streaming sink: when set, the audio thread forwards each callback's mono samples here
    // so a streaming ASR engine can consume them live. Zero overhead when None.
    chunk_sink: Arc<Mutex<Option<ChunkFn>>>,
}

impl AudioRecorder {
    pub fn create() -> Self {
        Self {
            recording: Arc::new(AtomicBool::new(false)),
            buffer: Arc::new(Mutex::new(Vec::with_capacity(RECORDING_BUFFER_CAPACITY))),
            stream_state: Mutex::new(None),
            level_sink: Arc::new(Mutex::new(None)),
            chunk_sink: Arc::new(Mutex::new(None)),
        }
    }

    // Registers a sink for live mic RMS (~30 Hz) used to drive the pill animation.
    // Read by the audio thread each emit tick, so it can be set before or after the stream exists.
    pub fn set_level_callback(&self, callback: LevelFn) {
        if let Ok(mut guard) = self.level_sink.lock() {
            *guard = Some(callback);
        }
    }

    // Registers a sink for live mono audio chunks at the device's source sample rate, used to
    // drive a streaming transcriber. Set before start(); clear after finish/cancel.
    pub fn set_chunk_callback(&self, callback: ChunkFn) {
        if let Ok(mut guard) = self.chunk_sink.lock() {
            *guard = Some(callback);
        }
    }

    pub fn clear_chunk_callback(&self) {
        if let Ok(mut guard) = self.chunk_sink.lock() {
            *guard = None;
        }
    }

    // Source sample rate of the currently-warmed input stream (None if warm_up not called yet).
    pub fn source_sample_rate(&self) -> Option<u32> {
        self.stream_state
            .lock()
            .ok()
            .and_then(|g| g.as_ref().map(|s| s.source_sample_rate))
    }

    // Creates the CoreAudio stream once; subsequent calls are a no-op.
    // Keeping the stream alive across recordings prevents macOS TCC
    // from re-validating mic permission on each start().
    fn ensure_stream(&self) -> Result<u32, String> {
        let mut guard = self.stream_state.lock().map_err(|e| format!("lock: {e}"))?;
        if let Some(ref s) = *guard {
            return Ok(s.source_sample_rate);
        }

        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or("no input device available")?;

        let config_range = pick_input_config(&device)?;
        let source_rate = config_range.max_sample_rate().0;
        let channels = config_range.channels() as usize;
        let config = config_range.with_max_sample_rate();

        let buf_ref = Arc::clone(&self.buffer);
        let rec_ref = Arc::clone(&self.recording);
        let level_ref = Arc::clone(&self.level_sink);
        let chunk_ref = Arc::clone(&self.chunk_sink);
        let emit_interval = (source_rate / LEVEL_EMIT_HZ).max(1);
        let mut frames_since_emit: u32 = 0;

        let stream = device
            .build_input_stream(
                &config.into(),
                move |data: &[f32], _: &cpal::InputCallbackInfo| {
                    if !rec_ref.load(Ordering::Relaxed) {
                        return;
                    }

                    // Build mono samples once: zero-copy slice for mono, downmix Vec otherwise.
                    let mono_owned: Option<Vec<f32>> = if channels > 1 {
                        Some(
                            data.chunks(channels)
                                .map(|frame| frame.iter().sum::<f32>() / channels as f32)
                                .collect(),
                        )
                    } else {
                        None
                    };
                    let mono: &[f32] = mono_owned.as_deref().unwrap_or(data);

                    if let Ok(mut buf) = buf_ref.try_lock() {
                        buf.extend_from_slice(mono);
                    }

                    // Forward to the streaming sink if active. Allocation only when a sink is set.
                    if let Ok(guard) = chunk_ref.try_lock() {
                        if let Some(ref sink) = *guard {
                            sink(mono.to_vec());
                        }
                    }

                    // Throttled RMS for the pill waveform.
                    let frame_count = (data.len() / channels.max(1)) as u32;
                    frames_since_emit += frame_count;
                    if frames_since_emit >= emit_interval && !data.is_empty() {
                        frames_since_emit = 0;
                        let sum_sq: f32 = data.iter().map(|s| s * s).sum();
                        let rms = (sum_sq / data.len() as f32).sqrt();
                        if let Ok(guard) = level_ref.try_lock() {
                            if let Some(ref sink) = *guard {
                                sink(rms);
                            }
                        }
                    }
                },
                |err| eprintln!("audio input error: {err}"),
                None,
            )
            .map_err(|e| format!("failed to build input stream: {e}"))?;

        *guard = Some(PersistentStream {
            stream,
            source_sample_rate: source_rate,
        });
        Ok(source_rate)
    }

    /// Pre-creates the CoreAudio stream so TCC validation happens early,
    /// not inside the hotkey callback where it would block the main thread.
    pub fn warm_up(&self) -> Result<(), String> {
        self.ensure_stream().map(|_| ())
    }

    pub fn start(&self) -> Result<(), String> {
        if self.recording.load(Ordering::Relaxed) {
            return Err("already recording".into());
        }

        self.ensure_stream()?;

        if let Ok(mut buf) = self.buffer.lock() {
            buf.clear();
        }

        self.recording.store(true, Ordering::Relaxed);

        let guard = self.stream_state.lock().map_err(|e| format!("lock: {e}"))?;
        if let Some(ref s) = *guard {
            s.stream
                .play()
                .map_err(|e| format!("failed to start stream: {e}"))?;
        }

        Ok(())
    }

    pub fn stop(&self) -> Result<Vec<f32>, String> {
        if !self.recording.load(Ordering::Relaxed) {
            return Err("not recording".into());
        }

        self.recording.store(false, Ordering::Relaxed);

        // Pause keeps the AudioUnit alive; mic indicator goes away
        let source_rate = {
            let guard = self.stream_state.lock().map_err(|e| format!("lock: {e}"))?;
            if let Some(ref s) = *guard {
                let _ = s.stream.pause();
            }
            guard
                .as_ref()
                .map(|s| s.source_sample_rate)
                .unwrap_or(TARGET_SAMPLE_RATE)
        };

        let samples = {
            let mut buf = self
                .buffer
                .lock()
                .map_err(|e| format!("buffer lock: {e}"))?;
            // Swap in a pre-reserved buffer so the next recording doesn't reallocate
            // on the realtime audio thread as it grows.
            std::mem::replace(&mut *buf, Vec::with_capacity(RECORDING_BUFFER_CAPACITY))
        };

        if samples.is_empty() {
            return Err("no audio captured".into());
        }

        if source_rate == TARGET_SAMPLE_RATE {
            return Ok(samples);
        }

        resample(&samples, source_rate, TARGET_SAMPLE_RATE)
    }
}

fn pick_input_config(device: &cpal::Device) -> Result<cpal::SupportedStreamConfigRange, String> {
    let mut configs: Vec<_> = device
        .supported_input_configs()
        .map_err(|e| format!("failed to query input configs: {e}"))?
        .collect();

    if configs.is_empty() {
        return Err("no supported input configurations".into());
    }

    configs.sort_by_key(|c| c.channels());
    Ok(configs[0])
}

fn resample(samples: &[f32], from_rate: u32, to_rate: u32) -> Result<Vec<f32>, String> {
    if samples.is_empty() {
        return Ok(Vec::new());
    }

    let params = SincInterpolationParameters {
        sinc_len: 256,
        f_cutoff: 0.95,
        interpolation: SincInterpolationType::Linear,
        oversampling_factor: 256,
        window: WindowFunction::BlackmanHarris2,
    };

    let ratio = to_rate as f64 / from_rate as f64;
    let chunk_size = 1024;

    let mut resampler = SincFixedIn::<f32>::new(ratio, 2.0, params, chunk_size, 1)
        .map_err(|e| format!("resampler init: {e}"))?;

    let mut output = Vec::with_capacity((samples.len() as f64 * ratio) as usize + chunk_size);

    for chunk in samples.chunks(chunk_size) {
        let mut padded = chunk.to_vec();
        if padded.len() < chunk_size {
            padded.resize(chunk_size, 0.0);
        }

        let result = resampler
            .process(&[padded], None)
            .map_err(|e| format!("resample: {e}"))?;

        output.extend_from_slice(&result[0]);
    }

    // The final chunk is zero-padded to chunk_size, so the resampler emits a short tail of
    // silence/ringing past the true audio. Trim to the expected resampled length.
    let expected_len = (samples.len() as f64 * ratio).round() as usize;
    output.truncate(expected_len.min(output.len()));

    Ok(output)
}
