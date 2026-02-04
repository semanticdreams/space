# Create speech

`POST` `/audio/speech`

Generates audio from the input text.

## Request Body

### Content Type: `application/json`

**Type**: object (6 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `model` | anyOf: string | string | Yes |  |  | One of the available [TTS models](/docs/models#tts): `tts-1`, `tts-1-hd` or `gpt-4o-mini-tts`. <br>  |
| `input` | string | Yes |  |  | The text to generate audio for. The maximum length is 4096 characters. |
| `instructions` | string | No |  |  | Control the voice of your generated audio with additional instructions. Does not work with `tts-1` or `tts-1-hd`. |
| `voice` | anyOf: string | string | Yes |  |  | The voice to use when generating the audio. Supported voices are `alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, `onyx`, `nova`, `sage`, `shimmer`, and `verse`. Previews of the voices are available in the [Text to speech guide](/docs/guides/text-to-speech#voice-options). |
| `response_format` | string | No | `mp3` | `mp3`, `opus`, `aac`, `flac`, `wav`, `pcm` | The format to audio in. Supported formats are `mp3`, `opus`, `aac`, `flac`, `wav`, and `pcm`. |
| `speed` | number | No | `1` |  | The speed of the generated audio. Select a value from `0.25` to `4.0`. `1.0` is the default. Does not work with `gpt-4o-mini-tts`. |
## Responses

### 200 - OK

#### Content Type: `application/octet-stream`

**Type**: `string`

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/audio/speech \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini-tts",
    "input": "The quick brown fox jumped over the lazy dog.",
    "voice": "alloy"
  }' \
  --output speech.mp3

```

#### python
```python
from pathlib import Path
import openai

speech_file_path = Path(__file__).parent / "speech.mp3"
with openai.audio.speech.with_streaming_response.create(
  model="gpt-4o-mini-tts",
  voice="alloy",
  input="The quick brown fox jumped over the lazy dog."
) as response:
  response.stream_to_file(speech_file_path)

```

#### javascript
```javascript
import fs from "fs";
import path from "path";
import OpenAI from "openai";

const openai = new OpenAI();

const speechFile = path.resolve("./speech.mp3");

async function main() {
  const mp3 = await openai.audio.speech.create({
    model: "gpt-4o-mini-tts",
    voice: "alloy",
    input: "Today is a wonderful day to build something people love!",
  });
  console.log(speechFile);
  const buffer = Buffer.from(await mp3.arrayBuffer());
  await fs.promises.writeFile(speechFile, buffer);
}
main();

```

#### csharp
```csharp
using System;
using System.IO;

using OpenAI.Audio;

AudioClient client = new(
    model: "gpt-4o-mini-tts",
    apiKey: Environment.GetEnvironmentVariable("OPENAI_API_KEY")
);

BinaryData speech = client.GenerateSpeech(
    text: "The quick brown fox jumped over the lazy dog.",
    voice: GeneratedSpeechVoice.Alloy
);

using FileStream stream = File.OpenWrite("speech.mp3");
speech.ToStream().CopyTo(stream);

```

