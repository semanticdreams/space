# conversation.item.input_audio_transcription.completed

This event is the output of audio transcription for user audio written to the 
user audio buffer. Transcription begins when the input audio buffer is 
committed by the client or server (in `server_vad` mode). Transcription runs 
asynchronously with Response creation, so this event may come before or after 
the Response events.

Realtime API models accept audio natively, and thus input transcription is a 
separate process run on a separate ASR (Automatic Speech Recognition) model, 
currently always `whisper-1`. Thus the transcript may diverge somewhat from 
the model's interpretation, and should be treated as a rough guide.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `conversation.item.input_audio_transcription.completed` | The event type, must be <br> `conversation.item.input_audio_transcription.completed`. <br>  |
| `item_id` | string | Yes |  |  | The ID of the user message item containing the audio. |
| `content_index` | integer | Yes |  |  | The index of the content part containing the audio. |
| `transcript` | string | Yes |  |  | The transcribed text. |
| `logprobs` | array of object (3 properties) | No |  |  | The log probabilities of the transcription. |


### Items in `logprobs` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `token` | string | Yes |  |  | The token that was used to generate the log probability. <br>  |
| `logprob` | number | Yes |  |  | The log probability of the token. <br>  |
| `bytes` | array of integer | Yes |  |  | The bytes that were used to generate the log probability. <br>  |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be
`conversation.item.input_audio_transcription.completed`.


**Type**: string

**Allowed values**: `conversation.item.input_audio_transcription.completed`

### `item_id` (required)

The ID of the user message item containing the audio.

**Type**: string

### `content_index` (required)

The index of the content part containing the audio.

**Type**: integer

### `transcript` (required)

The transcribed text.

**Type**: string

### `logprobs`

The log probabilities of the transcription.

**Type**: array of object (3 properties)

**Nullable**: Yes

## Example

```json
{
    "event_id": "event_2122",
    "type": "conversation.item.input_audio_transcription.completed",
    "item_id": "msg_003",
    "content_index": 0,
    "transcript": "Hello, how are you?"
}

```

