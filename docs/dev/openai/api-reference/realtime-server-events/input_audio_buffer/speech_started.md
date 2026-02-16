# input_audio_buffer.speech_started

Sent by the server when in `server_vad` mode to indicate that speech has been 
detected in the audio buffer. This can happen any time audio is added to the 
buffer (unless speech is already detected). The client may want to use this 
event to interrupt audio playback or provide visual feedback to the user. 

The client should expect to receive a `input_audio_buffer.speech_stopped` event 
when speech stops. The `item_id` property is the ID of the user message item 
that will be created when speech stops and will also be included in the 
`input_audio_buffer.speech_stopped` event (unless the client manually commits 
the audio buffer during VAD activation).


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `input_audio_buffer.speech_started` | The event type, must be `input_audio_buffer.speech_started`. |
| `audio_start_ms` | integer | Yes |  |  | Milliseconds from the start of all audio written to the buffer during the  <br> session when speech was first detected. This will correspond to the  <br> beginning of audio sent to the model, and thus includes the  <br> `prefix_padding_ms` configured in the Session. <br>  |
| `item_id` | string | Yes |  |  | The ID of the user message item that will be created when speech stops. <br>  |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `input_audio_buffer.speech_started`.

**Type**: string

**Allowed values**: `input_audio_buffer.speech_started`

### `audio_start_ms` (required)

Milliseconds from the start of all audio written to the buffer during the 
session when speech was first detected. This will correspond to the 
beginning of audio sent to the model, and thus includes the 
`prefix_padding_ms` configured in the Session.


**Type**: integer

### `item_id` (required)

The ID of the user message item that will be created when speech stops.


**Type**: string

## Example

```json
{
    "event_id": "event_1516",
    "type": "input_audio_buffer.speech_started",
    "audio_start_ms": 1000,
    "item_id": "msg_003"
}

```

