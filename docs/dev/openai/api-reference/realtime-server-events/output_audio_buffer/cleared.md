# output_audio_buffer.cleared

**WebRTC Only:** Emitted when the output audio buffer is cleared. This happens either in VAD
mode when the user has interrupted (`input_audio_buffer.speech_started`),
or when the client has emitted the `output_audio_buffer.clear` event to manually
cut off the current audio response.
[Learn more](/docs/guides/realtime-model-capabilities#client-and-server-events-for-audio-in-webrtc).


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `output_audio_buffer.cleared` | The event type, must be `output_audio_buffer.cleared`. |
| `response_id` | string | Yes |  |  | The unique ID of the response that produced the audio. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `output_audio_buffer.cleared`.

**Type**: string

**Allowed values**: `output_audio_buffer.cleared`

### `response_id` (required)

The unique ID of the response that produced the audio.

**Type**: string

## Example

```json
{
    "event_id": "event_abc123",
    "type": "output_audio_buffer.cleared",
    "response_id": "resp_abc123"
}

```

