# input_audio_buffer.commit

Send this event to commit the user input audio buffer, which will create a 
new user message item in the conversation. This event will produce an error 
if the input audio buffer is empty. When in Server VAD mode, the client does 
not need to send this event, the server will commit the audio buffer 
automatically.

Committing the input audio buffer will trigger input audio transcription 
(if enabled in session configuration), but it will not create a response 
from the model. The server will respond with an `input_audio_buffer.committed` 
event.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `input_audio_buffer.commit` | The event type, must be `input_audio_buffer.commit`. |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `input_audio_buffer.commit`.

**Type**: string

**Allowed values**: `input_audio_buffer.commit`

## Example

```json
{
    "event_id": "event_789",
    "type": "input_audio_buffer.commit"
}

```

