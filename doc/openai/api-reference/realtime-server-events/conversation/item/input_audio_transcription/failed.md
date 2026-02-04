# conversation.item.input_audio_transcription.failed

Returned when input audio transcription is configured, and a transcription 
request for a user message failed. These events are separate from other 
`error` events so that the client can identify the related Item.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `conversation.item.input_audio_transcription.failed` | The event type, must be <br> `conversation.item.input_audio_transcription.failed`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the user message item. |
| `content_index` | integer | Yes |  |  | The index of the content part containing the audio. |
| `error` | object (4 properties) | Yes |  |  | Details of the transcription error. |
|   ↳ `message` | string | No |  |  | A human-readable error message. |
|   ↳ `param` | string | No |  |  | Parameter related to the error, if any. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be
`conversation.item.input_audio_transcription.failed`.


**Type**: string

**Allowed values**: `conversation.item.input_audio_transcription.failed`

### `item_id` (required)

The ID of the user message item.

**Type**: string

### `content_index` (required)

The index of the content part containing the audio.

**Type**: integer

### `error` (required)

Details of the transcription error.

**Type**: object (4 properties)

**Nested Properties**:

* `type`, `code`, `message`, `param`

## Example

```json
{
    "event_id": "event_2324",
    "type": "conversation.item.input_audio_transcription.failed",
    "item_id": "msg_003",
    "content_index": 0,
    "error": {
        "type": "transcription_error",
        "code": "audio_unintelligible",
        "message": "The audio could not be transcribed.",
        "param": null
    }
}

```

