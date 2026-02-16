# input_audio_buffer.speech_stopped

Returned in `server_vad` mode when the server detects the end of speech in 
the audio buffer. The server will also send an `conversation.item.created` 
event with the user message item that is created from the audio buffer.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `input_audio_buffer.speech_stopped` | The event type, must be `input_audio_buffer.speech_stopped`. |
| `audio_end_ms` | integer | Yes |  |  | Milliseconds since the session started when speech stopped. This will  <br> correspond to the end of audio sent to the model, and thus includes the  <br> `min_silence_duration_ms` configured in the Session. <br>  |
| `item_id` | string | Yes |  |  | The ID of the user message item that will be created. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `input_audio_buffer.speech_stopped`.

**Type**: string

**Allowed values**: `input_audio_buffer.speech_stopped`

### `audio_end_ms` (required)

Milliseconds since the session started when speech stopped. This will 
correspond to the end of audio sent to the model, and thus includes the 
`min_silence_duration_ms` configured in the Session.


**Type**: integer

### `item_id` (required)

The ID of the user message item that will be created.

**Type**: string

## Example

```json
{
    "event_id": "event_1718",
    "type": "input_audio_buffer.speech_stopped",
    "audio_end_ms": 2000,
    "item_id": "msg_003"
}

```

