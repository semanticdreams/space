# output_audio_buffer.clear

**WebRTC Only:** Emit to cut off the current audio response. This will trigger the server to
stop generating audio and emit a `output_audio_buffer.cleared` event. This 
event should be preceded by a `response.cancel` client event to stop the 
generation of the current response.
[Learn more](/docs/guides/realtime-model-capabilities#client-and-server-events-for-audio-in-webrtc).


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | The unique ID of the client event used for error handling. |
| `type` | string | Yes |  | `output_audio_buffer.clear` | The event type, must be `output_audio_buffer.clear`. |

## Property Details

### `event_id`

The unique ID of the client event used for error handling.

**Type**: string

### `type` (required)

The event type, must be `output_audio_buffer.clear`.

**Type**: string

**Allowed values**: `output_audio_buffer.clear`

## Example

```json
{
    "event_id": "optional_client_event_id",
    "type": "output_audio_buffer.clear"
}

```

