# Stream Event (transcript.text.delta)

Emitted when there is an additional text delta. This is also the first event emitted when the transcription starts. Only emitted when you [create a transcription](/docs/api-reference/audio/create-transcription) with the `Stream` parameter set to `true`.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `transcript.text.delta` | The type of the event. Always `transcript.text.delta`. <br>  |
| `delta` | string | Yes |  |  | The text delta that was additionally transcribed. <br>  |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the delta. Only included if you [create a transcription](/docs/api-reference/audio/create-transcription) with the `include[]` parameter set to `logprobs`. <br>  |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | No |  |  | The token that was used to generate the log probability. <br>  |
| `logprob` | number | No |  |  | The log probability of the token. <br>  |
| `bytes` | array | No |  |  | The bytes that were used to generate the log probability. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `transcript.text.delta`.


**Type**: string

**Allowed values**: `transcript.text.delta`

### `delta` (required)

The text delta that was additionally transcribed.


**Type**: string

### `logprobs`

The log probabilities of the delta. Only included if you [create a transcription](/docs/api-reference/audio/create-transcription) with the `include[]` parameter set to `logprobs`.


**Type**: array of object (3 properties)

## Example

```json
{
  "type": "transcript.text.delta",
  "delta": " wonderful"
}

```

