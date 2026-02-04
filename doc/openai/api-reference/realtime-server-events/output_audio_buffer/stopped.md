# output_audio_buffer.stopped

**WebRTC Only:** Emitted when the output audio buffer has been completely drained on the server,
and no more audio is forthcoming. This event is emitted after the full response
data has been sent to the client (`response.done`).
[Learn more](/docs/guides/realtime-model-capabilities#client-and-server-events-for-audio-in-webrtc).


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `output_audio_buffer.stopped` | The event type, must be `output_audio_buffer.stopped`. |
| `response_id` | string | Yes |  |  | The unique ID of the response that produced the audio. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `output_audio_buffer.stopped`.

**Type**: string

**Allowed values**: `output_audio_buffer.stopped`

### `response_id` (required)

The unique ID of the response that produced the audio.

**Type**: string

## Example

```json
{
    "event_id": "event_abc123",
    "type": "output_audio_buffer.stopped",
    "response_id": "resp_abc123"
}

```

