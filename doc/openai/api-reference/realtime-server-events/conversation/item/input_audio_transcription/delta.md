# conversation.item.input_audio_transcription.delta

Returned when the text value of an input audio transcription content part is updated.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `conversation.item.input_audio_transcription.delta` | The event type, must be `conversation.item.input_audio_transcription.delta`. |
| `item_id` | string | Yes |  |  | The ID of the item. |
| `content_index` | integer | No |  |  | The index of the content part in the item's content array. |
| `delta` | string | No |  |  | The text delta. |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the transcription. |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token that was used to generate the log probability. <br>  |
| `logprob` | number | Yes |  |  | The log probability of the token. <br>  |
| `bytes` | array of integer | Yes |  |  | The bytes that were used to generate the log probability. <br>  |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `conversation.item.input_audio_transcription.delta`.

**Type**: string

**Allowed values**: `conversation.item.input_audio_transcription.delta`

### `item_id` (required)

The ID of the item.

**Type**: string

### `content_index`

The index of the content part in the item's content array.

**Type**: integer

### `delta`

The text delta.

**Type**: string

### `logprobs`

The log probabilities of the transcription.

**Type**: array of object (3 properties)

**Nullable**: Yes

## Example

```json
{
  "type": "conversation.item.input_audio_transcription.delta",
  "event_id": "event_001",
  "item_id": "item_001",
  "content_index": 0,
  "delta": "Hello"
}

```

