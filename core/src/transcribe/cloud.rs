use std::time::Instant;

use super::engine::TranscriptionResult;

const OPENAI_URL: &str = "https://api.openai.com/v1/audio/transcriptions";
const OPENAI_MODELS_URL: &str = "https://api.openai.com/v1/models";
const BOUNDARY: &str = "TapTalkBoundary7MA4YWxkTrZu0gW";

/// Validate the OpenAI API key by calling the models endpoint.
/// Returns a human-readable status string on success.
pub fn test_cloud_connection(api_key: &str) -> Result<String, String> {
    let resp = ureq::get(OPENAI_MODELS_URL)
        .header("Authorization", format!("Bearer {api_key}"))
        .call()
        .map_err(|e| format!("{e}"))?;

    // Consume body to release connection
    let body = resp.into_body().read_to_string().unwrap_or_default();

    let has_whisper = body.contains("whisper-1");
    if has_whisper {
        Ok("Connected · whisper-1 available".to_string())
    } else {
        Ok("Connected".to_string())
    }
}

/// Transcribe audio samples via OpenAI Whisper API.
pub fn transcribe_cloud(
    samples: &[f32],
    language: Option<&str>,
    model: &str,
    api_key: &str,
) -> Result<TranscriptionResult, String> {
    let start = Instant::now();

    let wav = encode_wav(samples)?;
    let body = build_multipart(&wav, model, language);
    let content_type = format!("multipart/form-data; boundary={BOUNDARY}");

    let response = ureq::post(OPENAI_URL)
        .header("Authorization", format!("Bearer {api_key}"))
        .header("Content-Type", content_type)
        .send(&body[..])
        .map_err(|e| format!("OpenAI request: {e}"))?;

    let body_str = response
        .into_body()
        .read_to_string()
        .map_err(|e| format!("read response: {e}"))?;

    let text = extract_json_str(&body_str, "text")
        .ok_or_else(|| format!("missing 'text' in response: {body_str}"))?;

    let detected_lang = extract_json_str(&body_str, "language")
        .unwrap_or_else(|| language.unwrap_or("unknown").to_string());

    Ok(TranscriptionResult {
        text: text.trim().to_string(),
        language: detected_lang,
        duration_ms: start.elapsed().as_millis() as u64,
    })
}

fn encode_wav(samples: &[f32]) -> Result<Vec<u8>, String> {
    const SAMPLE_RATE: u32 = 16_000;
    const CHANNELS: u16 = 1;
    const BITS: u16 = 16;
    const BYTE_RATE: u32 = SAMPLE_RATE * CHANNELS as u32 * BITS as u32 / 8;
    const BLOCK_ALIGN: u16 = CHANNELS * BITS / 8;

    let data_size = (samples.len() * 2) as u32;
    let mut buf = Vec::with_capacity(44 + data_size as usize);

    // RIFF header
    buf.extend_from_slice(b"RIFF");
    buf.extend_from_slice(&(36 + data_size).to_le_bytes());
    buf.extend_from_slice(b"WAVE");

    // fmt chunk
    buf.extend_from_slice(b"fmt ");
    buf.extend_from_slice(&16u32.to_le_bytes());
    buf.extend_from_slice(&1u16.to_le_bytes()); // PCM
    buf.extend_from_slice(&CHANNELS.to_le_bytes());
    buf.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
    buf.extend_from_slice(&BYTE_RATE.to_le_bytes());
    buf.extend_from_slice(&BLOCK_ALIGN.to_le_bytes());
    buf.extend_from_slice(&BITS.to_le_bytes());

    // data chunk
    buf.extend_from_slice(b"data");
    buf.extend_from_slice(&data_size.to_le_bytes());
    for &s in samples {
        let pcm = (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
        buf.extend_from_slice(&pcm.to_le_bytes());
    }

    Ok(buf)
}

fn build_multipart(wav: &[u8], model: &str, language: Option<&str>) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();

    append_str(
        &mut body,
        &format!(
            "--{BOUNDARY}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
        ),
    );
    body.extend_from_slice(wav);
    body.extend_from_slice(b"\r\n");

    append_field(&mut body, "model", model);

    // response_format for language detection
    append_field(&mut body, "response_format", "verbose_json");

    // language (skip for auto-detect)
    if let Some(lang) = language {
        if !lang.is_empty() {
            append_field(&mut body, "language", lang);
        }
    }

    append_str(&mut body, &format!("--{BOUNDARY}--\r\n"));
    body
}

fn append_field(body: &mut Vec<u8>, name: &str, value: &str) {
    append_str(
        body,
        &format!(
            "--{BOUNDARY}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n"
        ),
    );
}

fn append_str(body: &mut Vec<u8>, s: &str) {
    body.extend_from_slice(s.as_bytes());
}

/// Minimal JSON string extractor — avoids adding serde_json dependency.
fn extract_json_str(json: &str, key: &str) -> Option<String> {
    let needle = format!("\"{}\"", key);
    let pos = json.find(&needle)?;
    let after_key = &json[pos + needle.len()..];
    let after_colon = after_key.trim_start().strip_prefix(':')?.trim_start();
    if !after_colon.starts_with('"') {
        return None;
    }
    let content = &after_colon[1..];
    let mut result = String::new();
    let mut chars = content.chars();
    loop {
        match chars.next()? {
            '\\' => match chars.next()? {
                '"' => result.push('"'),
                'n' => result.push('\n'),
                't' => result.push('\t'),
                '\\' => result.push('\\'),
                c => {
                    result.push('\\');
                    result.push(c);
                }
            },
            '"' => break,
            c => result.push(c),
        }
    }
    Some(result)
}
