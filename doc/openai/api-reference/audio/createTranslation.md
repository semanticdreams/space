# Create translation

`POST` `/audio/translations`

Translates audio into English.

## Request Body

### Content Type: `multipart/form-data`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `file` | file | Yes |  |  | The audio file object (not file name) translate, in one of these formats: flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, or webm. <br>  |
| `model` | anyOf: string | string | Yes |  |  | ID of the model to use. Only `whisper-1` (which is powered by our open source Whisper V2 model) is currently available. <br>  |
| `prompt` | string | No |  |  | An optional text to guide the model's style or continue a previous audio segment. The [prompt](/docs/guides/speech-to-text#prompting) should be in English. <br>  |
| `response_format` | string | No | `json` | `json`, `text`, `srt`, `verbose_json`, `vtt` | The format of the output, in one of these options: `json`, `text`, `srt`, `verbose_json`, or `vtt`. <br>  |
| `temperature` | number | No | `0` |  | The sampling temperature, between 0 and 1. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. If set to 0, the model will use [log probability](https://en.wikipedia.org/wiki/Log_probability) to automatically increase the temperature until certain thresholds are hit. <br>  |
## Responses

### 200 - OK

#### Content Type: `application/json`

**One of the following:**

##### Option 1:

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `text` | string | Yes |  |  |  |
##### Option 2:

**Type**: object (4 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `language` | string | Yes |  |  | The language of the output translation (always `english`). |
| `duration` | number | Yes |  |  | The duration of the input audio. |
| `text` | string | Yes |  |  | The translated text. |
| `segments` | array of object (10 properties) | No |  |  | Segments of the translated text and their corresponding details. |


### Items in `segments` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | integer | Yes |  |  | Unique identifier of the segment. |
| `seek` | integer | Yes |  |  | Seek offset of the segment. |
| `start` | number | Yes |  |  | Start time of the segment in seconds. |
| `end` | number | Yes |  |  | End time of the segment in seconds. |
| `text` | string | Yes |  |  | Text content of the segment. |
| `tokens` | array of integer | Yes |  |  | Array of token IDs for the text content. |
| `temperature` | number | Yes |  |  | Temperature parameter used for generating the segment. |
| `avg_logprob` | number | Yes |  |  | Average logprob of the segment. If the value is lower than -1, consider the logprobs failed. |
| `compression_ratio` | number | Yes |  |  | Compression ratio of the segment. If the value is greater than 2.4, consider the compression failed. |
| `no_speech_prob` | number | Yes |  |  | Probability of no speech in the segment. If the value is higher than 1.0 and the `avg_logprob` is below -1, consider this segment silent. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/audio/translations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: multipart/form-data" \
  -F file="@/path/to/file/german.m4a" \
  -F model="whisper-1"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

audio_file = open("speech.mp3", "rb")
transcript = client.audio.translations.create(
  model="whisper-1",
  file=audio_file
)

```

#### javascript
```javascript
import fs from "fs";
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
    const translation = await openai.audio.translations.create({
        file: fs.createReadStream("speech.mp3"),
        model: "whisper-1",
    });

    console.log(translation.text);
}
main();

```

#### csharp
```csharp
using System;

using OpenAI.Audio;

string audioFilePath = "audio.mp3";

AudioClient client = new(
    model: "whisper-1",
    apiKey: Environment.GetEnvironmentVariable("OPENAI_API_KEY")
);

AudioTranscription transcription = client.TranscribeAudio(audioFilePath);

Console.WriteLine($"{transcription.Text}");

```

### Response Example

```json
{
  "text": "Hello, my name is Wolfgang and I come from Germany. Where are you heading today?"
}

```

