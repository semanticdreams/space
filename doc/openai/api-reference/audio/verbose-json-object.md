# The transcription object (Verbose JSON)

Represents a verbose json transcription response returned by model, based on the provided input.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| **`duration`** | number | The duration of the input audio. |
| **`language`** | string | The language of the input audio. |
| **`text`** | string | The transcribed text. |
| **`segments`** | array | Segments of the transcribed text and their corresponding details. |
| **`words`** | array | Extracted words and their corresponding timestamps. |

### Items in `segments` array

| Property | Type | Description |
|----------|------|-------------|
| **`id`** | integer | The segment ID. |
| **`seek`** | integer | The seek position. |
| **`start`** | number | The start time of the segment. |
| **`end`** | number | The end time of the segment. |
| **`text`** | string | The transcribed text segment. |
| **`tokens`** | array | Token IDs for the segment. |
| **`temperature`** | number | The temperature used for generation. |
| **`avg_logprob`** | number | The average log probability of the segment. |
| **`compression_ratio`** | number | The compression ratio. |
| **`no_speech_prob`** | number | The probability of no speech in the segment. |

### Items in `words` array

| Property | Type | Description |
|----------|------|-------------|
| **`word`** | string | The individual word. |
| **`start`** | number | The start time of the word. |
| **`end`** | number | The end time of the word. |
| **`confidence`** | number | Confidence score for the word recognition. |

## Example

```json
{
  "task": "transcribe",
  "language": "english",
  "duration": 8.470000267028809,
  "text": "The beach was a popular spot on a hot summer day. People were swimming in the ocean, building sandcastles, and playing beach volleyball.",
  "segments": [
    {
      "id": 0,
      "seek": 0,
      "start": 0,
      "end": 3.319999933242798,
      "text": " The beach was a popular spot on a hot summer day.",
      "tokens": [
        50364,
        440,
        7534,
        390,
        257,
        3743,
        4008,
        322,
        257,
        2368,
        4266,
        786,
        13,
        50530
      ],
      "temperature": 0,
      "avg_logprob": -0.2860786020755768,
      "compression_ratio": 1.2363636493682861,
      "no_speech_prob": 0.00985979475080967
    }
  ]
}
```

