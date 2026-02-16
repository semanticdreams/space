# response.audio_transcript.done

Returned when the model-generated transcription of audio output is done
streaming. Also emitted when a Response is interrupted, incomplete, or
cancelled.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `response.audio_transcript.done` | The event type, must be `response.audio_transcript.done`. |
| `response_id` | string | Yes |  |  | The ID of the response. |
| `item_id` | string | Yes |  |  | The ID of the item. |
| `output_index` | integer | Yes |  |  | The index of the output item in the response. |
| `content_index` | integer | Yes |  |  | The index of the content part in the item's content array. |
| `transcript` | string | Yes |  |  | The final transcript of the audio. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `response.audio_transcript.done`.

**Type**: string

**Allowed values**: `response.audio_transcript.done`

### `response_id` (required)

The ID of the response.

**Type**: string

### `item_id` (required)

The ID of the item.

**Type**: string

### `output_index` (required)

The index of the output item in the response.

**Type**: integer

### `content_index` (required)

The index of the content part in the item's content array.

**Type**: integer

### `transcript` (required)

The final transcript of the audio.

**Type**: string

## Example

```json
{
    "event_id": "event_4748",
    "type": "response.audio_transcript.done",
    "response_id": "resp_001",
    "item_id": "msg_008",
    "output_index": 0,
    "content_index": 0,
    "transcript": "Hello, how can I assist you today?"
}

```

