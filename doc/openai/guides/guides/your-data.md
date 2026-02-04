Data controls in the OpenAI platform
====================================

Understand how OpenAI uses your data, and how you can control it.

Understand how OpenAI uses your data, and how you can control it.

Your data is your data. As of March 1, 2023, data sent to the OpenAI API is not used to train or improve OpenAI models (unless you explicitly opt in to share data with us).

Types of data stored with the OpenAI API
----------------------------------------

When using the OpenAI API, data may be stored as:

*   **Abuse monitoring logs:** Logs generated from your use of the platform, necessary for OpenAI to enforce our [API data usage policies](https://openai.com/policies/api-data-usage-policies) and mitigate harmful uses of AI.
*   **Application state:** Data persisted from some API features in order to fulfill the task or request.

Data retention controls for abuse monitoring
--------------------------------------------

Abuse monitoring logs may contain certain customer content, such as prompts and responses, as well as metadata derived from that customer content, such as classifier outputs. By default, abuse monitoring logs are generated for all API feature usage and retained for up to 30 days.

Eligible customers may have their customer content excluded from these abuse monitoring logs by getting approved for the [Zero Data Retention](#zero-data-retention) or [Modified Abuse Monitoring](#modified-abuse-monitoring) controls. Currently, these controls are subject to prior approval by OpenAI and acceptance of additional requirements. Approved customers may select between Modified Abuse Monitoring or Zero Data Retention for their API Organization or project.

Customers who enable Modified Abuse Monitoring or Zero Data Retention are responsible for ensuring their users abide by OpenAI's policies for safe and responsible use of AI and complying with any moderation and reporting requirements under applicable law.

Get in touch with our [sales team](https://openai.com/contact-sales) to learn more about these offerings and inquire about eligibility.

### Modified Abuse Monitoring

Modified Abuse Monitoring excludes customer content (other than image and file inputs in rare cases, as described [below](#image-and-file-inputs)) from abuse monitoring logs, while still allowing the customer to take advantage of the full capabilities of the OpenAI platform.

When Modified Abuse Monitoring is enabled, customers may use any available OpenAI endpoints, including those that require data persistence to function. When using these endpoints, customer content that is retained for application state will be subject to other data controls, such as data residency, selected by the customer. However, customer content that is flagged by classifiers will not be retained in abuse monitoring logs or be subject to manual abuse review.

### Zero Data Retention

When Zero Data Retention is activated, modified abuse monitoring, as described above, will be applied in effect. Additionally, Zero Data Retention may prevent the usage of endpoints or capabilities that require application state to function.

### Storage requirements and retention controls per endpoint

|Endpoint|Data used for training|Abuse monitoring retention|Application state retention|Zero Data Retention eligibility|
|---|---|---|---|---|
|/v1/chat/completions|No|30 days|None, see below for exceptions|Yes, see below for limitations|
|/v1/responses|No|30 days|None, see below for exceptions|Yes, see below for limitations|
|/v1/assistants|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/threads|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/threads/messages|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/threads/runs|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/threads/runs/steps|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/vector_stores|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/images/generations|No|30 days|None|Yes, see below for limitations|
|/v1/images/edits|No|30 days|None|Yes, see below for limitations|
|/v1/images/variations|No|30 days|None|Yes, see below for limitations|
|/v1/embeddings|No|30 days|None|Yes|
|/v1/audio/transcriptions|No|None|None|Yes|
|/v1/audio/translations|No|None|None|Yes|
|/v1/audio/speech|No|30 days|None|Yes|
|/v1/files|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/fine_tuning/jobs|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/batches|No|30 days|Until deleted|No, if used application state will be stored|
|/v1/moderations|No|None|None|Yes|
|/v1/completions|No|30 days|None|Yes|
|/v1/realtime (beta)|No|30 days|None|Yes|

#### `/v1/chat/completions`

*   Audio outputs application state is stored for 1 hour to enable [multi-turn conversations](./audio).
*   When Structured Outputs is enabled, schemas provided (either as the `response_format` or in the function definition) will be stored. Other request content will not be stored.
*   When Zero Data Retention is enabled for an organization, the `store` parameter will always be treated as `false`, even if the request attempts to set the value to `true`.
*   See [image and file inputs](#image-and-file-inputs).

#### `/v1/responses`

*   The Responses API has a 30 day Application State retention period by default, or when the `store` parameter is set to `true`. Response data will be stored for at least 30 days.
*   When Zero Data Retention is enabled for an organization, the `store` parameter will always be treated as `false`, even if the request attempts to set the value to `true`.
*   Audio outputs application state is stored for 1 hour to enable [multi-turn conversations](./audio).
*   When Structured Outputs is enabled, schemas provided (either as the `response_format` or in the function definition) will be stored as Application State, even if Zero Data Retention is enabled.
*   See [image and file inputs](#image-and-file-inputs).

#### `/v1/assistants`, `/v1/threads`, and `/v1/vector_stores`

*   Objects related to the Assistants API are deleted from our servers 30 days after you delete them via the API or the dashboard. Objects that are not deleted via the API or dashboard are retained indefinitely.

#### `/v1/images`

*   Image generation is Zero Data Retention compatible when using `gpt-image-1`, not when using `dall-e-3` or `dall-e-2`.

#### Image and file inputs

Images and files may be uploaded as inputs to `/v1/responses` (including when using the Computer Use tool), `/v1/chat/completions`, and `/v1/images`. Image and file inputs are scanned for CSAM content upon submission. If the classifier detects potential CSAM content, the image will be retained for manual review, even if Zero Data Retention or Modified Abuse Monitoring is enabled.

#### Web Search

Web Search is not HIPAA eligible and is not covered by a BAA.

Data residency controls
-----------------------

Data residency controls are a project configuration option that allow you to configure the location of infrastructure OpenAI uses to provide services.

Contact our [sales team](https://openai.com/contact-sales) to see if you're eligible for using data residency controls.

### How does data residency work?

When data residency is enabled on your account, you can set a region for new projects you create in your account from the available regions listed below. If you use the supported endpoints, models, and snapshots listed below, your customer content (as defined in your services agreement) for that project will be stored at rest in the selected region to the extent the endpoint requires data persistence to function (such as /v1/batches).

If you select a region that supports regional processing, as specifically identified below, the services will perform inference for your Customer Content in the selected region as well.

Data residency does not apply to system data, which may be processed and stored outside the selected region. System data means account data, metadata, and usage data that do not contain Customer Content, which are collected by the services and used to manage and operate the services, such as account information or profiles of end users that directly access the services (e.g., your personnel), analytics, usage statistics, billing information, support requests, and structured output schema.

### Limitations

Data residency does not apply to: (a) any transmission or storage of Customer Content outside of the selected region caused by the location of an End User or Customer's infrastructure when accessing the services; (b) products, services, or content offered by parties other than OpenAI through the Services; or (c) any data other than Customer Content, such as system data.

If your selected Region does not support regional processing, as identified below, OpenAI may also process and temporarily store Customer Content outside of the Region to deliver the services.

### Additional requirements for non-US regions

To use data residency with any region other than the United States, you must be approved for abuse monitoring controls, and execute a Zero Data Retention amendment.

### How to use data residency

Data residency is configured per-project within your API Organization.

To configure data residency for regional storage, select the appropriate region from the dropdown when creating a new project.

In Europe, you must also send requests to the [https://eu.api.openai.com/](https://eu.api.openai.com/) base URL for the request to be processed in the region.

### Which models and features are eligible for data residency?

The following models and API services are eligible for data residency today for the regions specified below.

**Table 1: Regional data residency capabilities**

|Region|Regional storage|Regional processing|Requires modified abuse monitoring or ZDR|Default modes of entry|
|---|---|---|---|---|
|US|✅|✅|❌|Text, Audio, Voice, Image|
|Europe (EEA + Switzerland)|✅|✅|✅|Text, Audio, Voice, Image*|
|Canada|✅|❌|✅|Text, Audio, Voice, Image*|
|Japan|✅|❌|✅|Text, Audio, Voice, Image*|
|India|✅|❌|✅|Text, Audio, Voice, Image*|
|Singapore|✅|❌|✅|Text, Audio, Voice, Image*|
|South Korea|✅|❌|✅|Text, Audio, Voice, Image*|

\* Image support in these regions requires approval for enhanced Zero Data Retention or enhanced Modified Abuse Monitoring.

**Table 2: API endpoint and tool support**

|Supported services|Supported model snapshots|Supported region|
|---|---|---|
|/v1/chat/completions\|gpt-4.1-2025-04-14gpt-4.1-mini-2025-04-14gpt-4.1-nano-2025-04-14o3-mini-2025-01-31o3-2025-04-16o4-mini-2025-04-16o1-2024-12-17o1-mini-2024-09-12o1-previewgpt-4o-2024-11-20gpt-4o-2024-08-06gpt-4o-mini-2024-07-18gpt-4-turbo-2024-04-09gpt-4-0613gpt-3.5-turbo-0125|All|
|/v1/responses\|gpt-4.1-2025-04-14gpt-4.1-mini-2025-04-14gpt-4.1-nano-2025-04-14o3-2025-04-16o4-mini-2025-04-16o1-proo1-pro-2025-03-19computer-use-previewo3-mini-2025-01-31o1-2024-12-17o1-mini-2024-09-12o1-previewgpt-4o-2024-11-20gpt-4o-2024-08-06gpt-4o-mini-2024-07-18gpt-4-turbo-2024-04-09gpt-4-0613gpt-3.5-turbo-0125|All|
|/v1/images/generations|dall-e-3|All|
|/v1/audio/transcriptions /v1/audio/translations /v1/audio/speech|tts-1whisper-1gpt-4o-ttsgpt-4o-transcribegpt-4o-mini-transcribe|All|
|/v1/moderations|text-moderation-007omni-moderation-latest|All|
|/v1/batches|gpt-4.1-2025-04-14gpt-4.1-mini-2025-04-14gpt-4.1-nano-2025-04-14o3-2025-04-16o4-mini-2025-04-16o1-proo1-pro-2025-03-19o3-mini-2025-01-31o1-2024-12-17o1-mini-2024-09-12o1-previewgpt-4o-2024-11-20gpt-4o-2024-08-06gpt-4o-mini-2024-07-18gpt-4-turbo-2024-04-09gpt-4-0613gpt-3.5-turbo-0125|All|
|/v1/embeddings|text-embedding-3-smalltext-embedding-3-largetext-embedding-ada-002|All|
|/v1/fine_tuning/jobs /v1/files|gpt-4o-2024-08-06gpt-4o-mini-2024-07-18|US, EU|
|/v1/realtime (beta)|gpt-4o-realtime-preview-2024-12-17gpt-4o-mini-realtime-preview-2024-12-17|US|
|Scale Tier||All|
|Structured Outputs (excluding schema)||All|
|/v1/vector_stores||All|
|/v1/responses File Search||All|
|/v1/responses Web Search||All|
|File Search||All|
|File Uploads||All, when used with base64 file uploads|
|Supported Input Modalities||Text Image Audio/Voice|

#### \`/v1/chat/completions

Cannot set store=true in non-US regions