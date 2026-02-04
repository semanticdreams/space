# input_audio_buffer.clear

Send this event to clear the audio bytes in the buffer. The server will 
respond with an `input_audio_buffer.cleared` event.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `input_audio_buffer.clear` | The event type, must be `input_audio_buffer.clear`. |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `input_audio_buffer.clear`.

**Type**: string

**Allowed values**: `input_audio_buffer.clear`

## Example

```json
{
    "event_id": "event_012",
    "type": "input_audio_buffer.clear"
}

```

