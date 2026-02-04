Direct preference optimization
==============================

Fine-tune models for subjective decision-making by comparing model outputs.

[Direct Preference Optimization](https://arxiv.org/abs/2305.18290) (DPO) fine-tuning allows you to fine-tune models based on prompts and pairs of responses. This approach enables the model to learn from more subjective human preferences, optimizing for outputs that are more likely to be favored. DPO is currently only supported for text inputs and outputs.

Data format
-----------

Each example in your dataset should contain:

*   A prompt, like a user message.
*   A preferred output (an ideal assistant response).
*   A non-preferred output (a suboptimal assistant response).

The data should be formatted in JSONL format, with each line [representing an example](/docs/api-reference/fine-tuning/preference-input) in the following structure:

```json
{
  "input": {
    "messages": [
      {
        "role": "user",
        "content": "Hello, can you tell me how cold San Francisco is today?"
      }
    ],
    "tools": [],
    "parallel_tool_calls": true
  },
  "preferred_output": [
    {
      "role": "assistant",
      "content": "Today in San Francisco, it is not quite cold as expected. Morning clouds will give away to sunshine, with a high near 68°F (20°C) and a low around 57°F (14°C)."
    }
  ],
  "non_preferred_output": [
    {
      "role": "assistant",
      "content": "It is not particularly cold in San Francisco today."
    }
  ]
}
```

Currently, we only train on one-turn conversations for each example, where the preferred and non-preferred messages need to be the last assistant message.

Create a DPO fine-tune job
--------------------------

Uploading training data and using a model fine-tuned with DPO follows the [same flow described here](/docs/guides/fine-tuning).

To create a DPO fine-tune job, use the `method` field in the [fine-tuning job creation endpoint](/docs/api-reference/fine-tuning/create), where you can specify `type` as well as any associated `hyperparameters`. For DPO:

*   set the `type` parameter to `dpo`
*   optionally set the `hyperparameters` property with any options you'd like to configure.

The `beta` hyperparameter is a new option that is only available for DPO. It's a floating point number between `0` and `2` that controls how strictly the new model will adhere to its previous behavior, versus aligning with the provided preferences. A high number will be more conservative (favoring previous behavior), and a lower number will be more aggressive (favor the newly provided preferences more often).

You can also set this value to `auto` (the default) to use a value configured by the platform.

The example below shows how to configure a DPO fine-tuning job using the OpenAI SDK.

Create a fine-tuning job with DPO

```javascript
import OpenAI from "openai";

const openai = new OpenAI();

const job = await openai.fineTuning.jobs.create({
  training_file: "file-all-about-the-weather",
  model: "gpt-4o-2024-08-06",
  method: {
    type: "dpo",
    dpo: {
      hyperparameters: { beta: 0.1 },
    },
  },
});
```

```python
from openai import OpenAI

client = OpenAI()

job = client.fine_tuning.jobs.create(
    training_file="file-all-about-the-weather",
    model="gpt-4o-2024-08-06",
    method={
        "type": "dpo",
        "dpo": {
            "hyperparameters": {"beta": 0.1},
        },
    },
)
```

Use SFT and DPO together
------------------------

Currently, OpenAI offers [supervised fine-tuning (SFT)](/docs/guides/supervised-fine-tuning) as the default method for fine-tuning jobs. Performing SFT on your preferred responses (or a subset) before running another DPO job afterwards can significantly enhance model alignment and performance. By first fine-tuning the model on the desired responses, it can better identify correct patterns, providing a strong foundation for DPO to refine behavior.

A recommended workflow is as follows:

1.  Fine-tune the base model with SFT using a subset of your preferred responses. Focus on ensuring the data quality and representativeness of the tasks.
2.  Use the SFT fine-tuned model as the starting point, and apply DPO to adjust the model based on preference comparisons.

Next steps
----------

Now that you know the basics of DPO, explore these other methods as well.

[

Supervised fine-tuning

Fine-tune a model by providing correct outputs for sample inputs.

](/docs/guides/supervised-fine-tuning)[

Vision fine-tuning

Learn to fine-tune for computer vision with image inputs.

](/docs/guides/vision-fine-tuning)[

Reinforcement fine-tuning

Fine-tune a reasoning model by grading its outputs.

](/docs/guides/reinforcement-fine-tuning)