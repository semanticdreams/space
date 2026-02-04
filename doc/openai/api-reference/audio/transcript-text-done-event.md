# Stream Event (transcript.text.done)

Emitted when the transcription is complete. Contains the complete transcription text. Only emitted when you [create a transcription](/docs/api-reference/audio/create-transcription) with the `Stream` parameter set to `true`.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `transcript.text.done` | The type of the event. Always `transcript.text.done`. <br>  |
| `text` | string | Yes |  |  | The text that was transcribed. <br>  |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the individual tokens in the transcription. Only included if you [create a transcription](/docs/api-reference/audio/create-transcription) with the `include[]` parameter set to `logprobs`. <br>  |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | No |  |  | The token that was used to generate the log probability. <br>  |
| `logprob` | number | No |  |  | The log probability of the token. <br>  |
| `bytes` | array | No |  |  | The bytes that were used to generate the log probability. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `transcript.text.done`.


**Type**: string

**Allowed values**: `transcript.text.done`

### `text` (required)

The text that was transcribed.


**Type**: string

### `logprobs`

The log probabilities of the individual tokens in the transcription. Only included if you [create a transcription](/docs/api-reference/audio/create-transcription) with the `include[]` parameter set to `logprobs`.


**Type**: array of object (3 properties)

## Example

```json
{
  "type": "transcript.text.done",
  "text": "I see skies of blue and clouds of white, the bright blessed days, the dark sacred nights, and I think to myself, what a wonderful world."
}

```

