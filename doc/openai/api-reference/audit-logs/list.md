# List audit logs

`GET` `/organization/audit_logs`

List user actions and configuration changes within this organization.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `effective_at` | object (4 properties) | No | Return only events whose `effective_at` (Unix seconds) is in this range. |
| `project_ids[]` | array of string | No | Return only events for these projects. |
| `event_types[]` | array of string | No | Return only events with a `type` in one of these values. For example, `project.created`. For all options, see the documentation for the [audit log object](/docs/api-reference/audit-logs/object). |
| `actor_ids[]` | array of string | No | Return only events performed by these actors. Can be a user ID, a service account ID, or an api key tracking ID. |
| `actor_emails[]` | array of string | No | Return only events performed by users with these emails. |
| `resource_ids[]` | array of string | No | Return only events performed on these targets. For example, a project ID updated. |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `before` | string | No | A cursor for use in pagination. `before` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, starting with obj_foo, your subsequent call can include before=obj_foo in order to fetch the previous page of the list. <br>  |

## Responses

### 200 - Audit logs listed successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` |  |
| `data` | array of object (32 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The ID of this log. |
| `type` | string | Yes |  | `api_key.created`, `api_key.updated`, `api_key.deleted`, `checkpoint_permission.created`, `checkpoint_permission.deleted`, `invite.sent`, `invite.accepted`, `invite.deleted`, `login.succeeded`, `login.failed`, `logout.succeeded`, `logout.failed`, `organization.updated`, `project.created`, `project.updated`, `project.archived`, `service_account.created`, `service_account.updated`, `service_account.deleted`, `rate_limit.updated`, `rate_limit.deleted`, `user.added`, `user.updated`, `user.deleted` | The event type. |
| `effective_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of the event. |
| `project` | object (2 properties) | No |  |  | The project that the action was scoped to. Absent for actions not scoped to projects. |
| `actor` | object (3 properties) | Yes |  |  | The actor who performed the audit logged action. |
|   ↳ `api_key` | object (4 properties) | No |  |  | The API Key used to perform the audit logged action. |
|     ↳ `user` | object (2 properties) | No |  |  | The user who performed the audit logged action. |
|     ↳ `service_account` | object (1 property) | No |  |  | The service account that performed the audit logged action. |
| `api_key.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `api_key.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `api_key.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `checkpoint_permission.created` | object (2 properties) | No |  |  | The project and fine-tuned model checkpoint that the checkpoint permission was created for. |
| `checkpoint_permission.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `invite.sent` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `invite.accepted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `invite.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `login.failed` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `logout.failed` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `organization.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
|     ↳ `name` | string | No |  |  | The organization name. |
|     ↳ `settings` | object (2 properties) | No |  |  |  |
| `project.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `project.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `project.archived` | object (1 property) | No |  |  | The details for events with this `type`. |
| `rate_limit.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
|     ↳ `max_images_per_1_minute` | integer | No |  |  | The maximum images per minute. Only relevant for certain models. |
|     ↳ `max_audio_megabytes_per_1_minute` | integer | No |  |  | The maximum audio megabytes per minute. Only relevant for certain models. |
|     ↳ `max_requests_per_1_day` | integer | No |  |  | The maximum requests per day. Only relevant for certain models. |
|     ↳ `batch_1_day_max_input_tokens` | integer | No |  |  | The maximum batch input tokens per day. Only relevant for certain models. |
| `rate_limit.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `service_account.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `service_account.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `service_account.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `user.added` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `user.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `user.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `certificate.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `certificate.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `certificate.deleted` | object (3 properties) | No |  |  | The details for events with this `type`. |
|   ↳ `certificate` | string | No |  |  | The certificate content in PEM format. |
| `certificates.activated` | object (1 property) | No |  |  | The details for events with this `type`. |

### Items in `certificates` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  | The certificate ID. |
| `name` | string | No |  |  | The name of the certificate. |
| `certificates.deactivated` | object (1 property) | No |  |  | The details for events with this `type`. |

### Items in `certificates` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  | The certificate ID. |
| `name` | string | No |  |  | The name of the certificate. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/audit_logs \
-H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
-H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "list",
    "data": [
        {
            "id": "audit_log-xxx_yyyymmdd",
            "type": "project.archived",
            "effective_at": 1722461446,
            "actor": {
                "type": "api_key",
                "api_key": {
                    "type": "user",
                    "user": {
                        "id": "user-xxx",
                        "email": "user@example.com"
                    }
                }
            },
            "project.archived": {
                "id": "proj_abc"
            },
        },
        {
            "id": "audit_log-yyy__20240101",
            "type": "api_key.updated",
            "effective_at": 1720804190,
            "actor": {
                "type": "session",
                "session": {
                    "user": {
                        "id": "user-xxx",
                        "email": "user@example.com"
                    },
                    "ip_address": "127.0.0.1",
                    "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
                    "ja3": "a497151ce4338a12c4418c44d375173e",
                    "ja4": "q13d0313h3_55b375c5d22e_c7319ce65786",
                    "ip_address_details": {
                      "country": "US",
                      "city": "San Francisco",
                      "region": "California",
                      "region_code": "CA",
                      "asn": "1234",
                      "latitude": "37.77490",
                      "longitude": "-122.41940"
                    }
                }
            },
            "api_key.updated": {
                "id": "key_xxxx",
                "data": {
                    "scopes": ["resource_2.operation_2"]
                }
            },
        }
    ],
    "first_id": "audit_log-xxx__20240101",
    "last_id": "audit_log_yyy__20240101",
    "has_more": true
}

```

