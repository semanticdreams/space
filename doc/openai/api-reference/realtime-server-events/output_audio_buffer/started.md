# output_audio_buffer.started

**WebRTC Only:** Emitted when the server begins streaming audio to the client. This event is
emitted after an audio content part has been added (`response.content_part.added`)
to the response.
[Learn more](/docs/guides/realtime-model-capabilities#client-and-server-events-for-audio-in-webrtc).


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `output_audio_buffer.started` | The event type, must be `output_audio_buffer.started`. |
| `response_id` | string | Yes |  |  | The unique ID of the response that produced the audio. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `output_audio_buffer.started`.

**Type**: string

**Allowed values**: `output_audio_buffer.started`

### `response_id` (required)

The unique ID of the response that produced the audio.

**Type**: string

## Example

```json
{
    "event_id": "event_abc123",
    "type": "output_audio_buffer.started",
    "response_id": "resp_abc123"
}

```

