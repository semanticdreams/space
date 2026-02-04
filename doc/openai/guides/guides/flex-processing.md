Flex processing

Beta

=======================

Optimize costs with flex processing.

Flex processing provides significantly lower costs for [Chat Completions](/docs/api-reference/chat) or [Responses](/docs/api-reference/responses) requests in exchange for slower response times and occasional resource unavailability. It is ideal for non-production or lower-priority tasks such as model evaluations, data enrichment, or asynchronous workloads.

Token inputs and outputs are [priced](/docs/pricing) at [Batch API rates](/docs/guides/batch), with additional discounts from [prompt caching](/docs/guides/prompt-caching).

Flex processing is in beta, and currently only available for [o3](/docs/models/o3) and [o4-mini](/docs/models/o4-mini) models.

API usage
---------

Set the `service_tier` parameter to `flex` in your API request ([Chat](/docs/api-reference/chat) or [Responses](/docs/api-reference/responses)) to take advantage of Flex processing.

Flex processing example

```javascript
import OpenAI from "openai";
const client = new OpenAI({
    timeout: 15 * 1000 * 60, // Increase default timeout to 15 minutes
});

const response = await client.responses.create({
    model: "o3",
    instructions: "List and describe all the metaphors used in this book.",
    input: "<very long text of book here>",
    service_tier: "flex",
    timeout: 15 * 1000 * 60, // Can override timeout per request
});

console.log(response.output_text);
```

```python
from openai import OpenAI
client = OpenAI(
    # increase default timeout to 15 minutes (from 10 minutes)
    timeout=900.0
)

# you can override the max timeout per request as well
response = client.with_options(timeout=900.0).responses.create(
    model="o3",
    instructions="List and describe all the metaphors used in this book.",
    input="<very long text of book here>",
    service_tier="flex",
)

print(response.output_text)
```

```bash
curl https://api.openai.com/v1/responses \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "o3",
    "instructions": "List and describe all the metaphors used in this book.",
    "input": "<very long text of book here>",
    "service_tier": "flex"
  }'
```

#### API request timeouts

Due to slower processing speeds with Flex processing, request timeouts are more likely. Here are some considerations for handling timeouts:

*   **Default timeout**: The default timeout is **10 minutes** when making API requests with an official OpenAI SDK. You may need to increase this timeout for lengthy prompts or complex tasks.
*   **Configuring timeouts**: Each SDK will provide a parameter to increase this timeout. In the Python and JavaScript SDKs, this is `timeout` as shown in the code samples above.
*   **Automatic retries**: The OpenAI SDKs automatically retry requests that result in a `408 Request Timeout` error code twice before throwing an exception.

Resource unavailable errors
---------------------------

Flex processing may sometimes lack sufficient resources to handle your requests, resulting in a `429 Resource Unavailable` error code. **You will not be charged when this occurs.**

When encountering Resource Unavailable errors, consider these strategies:

*   **Retry requests with exponential backoff**: This approach is suitable for workloads that can tolerate delays and aims to minimize costs. For implementation details, see [this cookbook](https://cookbook.openai.com/examples/how_to_handle_rate_limits?utm_source=chatgpt.com#retrying-with-exponential-backoff).
    
*   **Fallback to standard request**: Switching to the default tier is recommended if timely completion is important and occasional higher costs are acceptable. Set `service_tier` to `auto` in your request to do this, or remove the `service_tier` parameter to use the default tier.