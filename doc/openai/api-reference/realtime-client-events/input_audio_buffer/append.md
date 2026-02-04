# input_audio_buffer.append

Send this event to append audio bytes to the input audio buffer. The audio 
buffer is temporary storage you can write to and later commit. In Server VAD 
mode, the audio buffer is used to detect speech and the server will decide 
when to commit. When Server VAD is disabled, you must commit the audio buffer
manually.

The client may choose how much audio to place in each event up to a maximum 
of 15 MiB, for example streaming smaller chunks from the client may allow the 
VAD to be more responsive. Unlike made other client events, the server will 
not send a confirmation response to this event.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `input_audio_buffer.append` | The event type, must be `input_audio_buffer.append`. |
| `audio` | string | Yes |  |  | Base64-encoded audio bytes. This must be in the format specified by the  <br> `input_audio_format` field in the session configuration. <br>  |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `input_audio_buffer.append`.

**Type**: string

**Allowed values**: `input_audio_buffer.append`

### `audio` (required)

Base64-encoded audio bytes. This must be in the format specified by the 
`input_audio_format` field in the session configuration.


**Type**: string

## Example

```json
{
    "event_id": "event_456",
    "type": "input_audio_buffer.append",
    "audio": "Base64EncodedAudioData"
}

```

