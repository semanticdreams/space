# The transcription object (JSON)

Represents a transcription response returned by model, based on the provided input.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `text` | string | Yes |  |  | The transcribed text. |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the tokens in the transcription. Only returned with the models `gpt-4o-transcribe` and `gpt-4o-mini-transcribe` if `logprobs` is added to the `include` array. <br>  |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | No |  |  | The token in the transcription. |
| `logprob` | number | No |  |  | The log probability of the token. |
| `bytes` | array of number | No |  |  | The bytes of the token. |

## Property Details

### `text` (required)

The transcribed text.

**Type**: string

### `logprobs`

The log probabilities of the tokens in the transcription. Only returned with the models `gpt-4o-transcribe` and `gpt-4o-mini-transcribe` if `logprobs` is added to the `include` array.


**Type**: array of object (3 properties)

## Example

```json
{
  "text": "Imagine the wildest idea that you've ever had, and you're curious about how it might scale to something that's a 100, a 1,000 times bigger. This is a place where you can get to do that."
}

```

