use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use rubato::{SincFixedIn, SincInterpolationParameters, SincInterpolationType, Resampler, WindowFunction};

const TARGET_SAMPLE_RATE: u32 = 16_000;

struct RecordingState {
    buffer: Arc<Mutex<Vec<f32>>>,
    _stream: cpal::Stream,
    source_sample_rate: u32,
}

// cpal::Stream is Send but not Sync — Mutex wrapping makes this safe
unsafe impl Send for RecordingState {}
unsafe impl Sync for RecordingState {}

pub struct AudioRecorder {
    recording: AtomicBool,
    state: Mutex<Option<RecordingState>>,
}

impl AudioRecorder {
    pub fn create() -> Self {
        Self {
            recording: AtomicBool::new(false),
            state: Mutex::new(None),
        }
    }

    pub fn is_recording(&self) -> bool {
        self.recording.load(Ordering::Relaxed)
    }

    pub fn start(&self) -> Result<(), String> {
        if self.recording.load(Ordering::Relaxed) {
            return Err("already recording".into());
        }

        let host = cpal::default_host();
        let device = host.default_input_device()
            .ok_or("no input device available")?;

        let config_range = pick_input_config(&device)?;
        let source_rate = config_range.max_sample_rate().0;
        let channels = config_range.channels() as usize;
        let config = config_range.with_max_sample_rate();

        let buffer: Arc<Mutex<Vec<f32>>> = Arc::new(
            Mutex::new(Vec::with_capacity(source_rate as usize * 30))
        );
        let buffer_ref = Arc::clone(&buffer);

        let stream = device.build_input_stream(
            &config.into(),
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                if let Ok(mut buf) = buffer_ref.try_lock() {
                    if channels == 1 {
                        buf.extend_from_slice(data);
                    } else {
                        for frame in data.chunks(channels) {
                            let sum: f32 = frame.iter().sum();
                            buf.push(sum / channels as f32);
                        }
                    }
                }
            },
            |err| eprintln!("audio input error: {err}"),
            None,
        ).map_err(|e| format!("failed to build input stream: {e}"))?;

        stream.play().map_err(|e| format!("failed to start stream: {e}"))?;
        self.recording.store(true, Ordering::Relaxed);

        let mut state = self.state.lock().map_err(|e| format!("lock: {e}"))?;
        *state = Some(RecordingState {
            buffer,
            _stream: stream,
            source_sample_rate: source_rate,
        });

        Ok(())
    }

    pub fn stop(&self) -> Result<Vec<f32>, String> {
        if !self.recording.load(Ordering::Relaxed) {
            return Err("not recording".into());
        }

        self.recording.store(false, Ordering::Relaxed);

        let mut state_guard = self.state.lock().map_err(|e| format!("lock: {e}"))?;
        let recording = state_guard.take().ok_or("no recording state")?;
        let source_rate = recording.source_sample_rate;

        // Drop stream to stop audio callback, then extract buffer
        drop(recording._stream);

        let samples = Arc::try_unwrap(recording.buffer)
            .map_err(|_| "buffer still referenced")?
            .into_inner()
            .map_err(|e| format!("buffer lock: {e}"))?;

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
    let mut configs: Vec<_> = device.supported_input_configs()
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

    let mut resampler = SincFixedIn::<f32>::new(
        ratio,
        2.0,
        params,
        chunk_size,
        1,
    ).map_err(|e| format!("resampler init: {e}"))?;

    let mut output = Vec::with_capacity((samples.len() as f64 * ratio) as usize + chunk_size);

    for chunk in samples.chunks(chunk_size) {
        let mut padded = chunk.to_vec();
        if padded.len() < chunk_size {
            padded.resize(chunk_size, 0.0);
        }

        let result = resampler.process(&[padded], None)
            .map_err(|e| format!("resample: {e}"))?;

        output.extend_from_slice(&result[0]);
    }

    Ok(output)
}
