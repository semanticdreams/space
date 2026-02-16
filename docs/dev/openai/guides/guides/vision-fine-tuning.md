Vision fine-tuning
==================

Fine-tune models for better image understanding.

Vision fine-tuning uses image inputs for [supervised fine-tuning](/docs/guides/supervised-fine-tuning) to improve the model's understanding of image inputs. This guide will take you through this subset of SFT, and outline some of the important considerations for fine-tuning with image inputs.

Data format
-----------

Just as you can [send one or many image inputs and create model responses based on them](/docs/guides/vision), you can include those same message types within your JSONL training data files. Images can be provided either as HTTP URLs or data URLs containing Base64-encoded images.

Here's an example of an image message on a line of your JSONL file. Below, the JSON object is expanded for readability, but typically this JSON would appear on a single line in your data file:

```json
{
  "messages": [
    {
      "role": "system",
      "content": "You are an assistant that identifies uncommon cheeses."
    },
    {
      "role": "user",
      "content": "What is this cheese?"
    },
    {
      "role": "user",
      "content": [
        {
          "type": "image_url",
          "image_url": {
            "url": "https://upload.wikimedia.org/wikipedia/commons/3/36/Danbo_Cheese.jpg"
          }
        }
      ]
    },
    {
      "role": "assistant",
      "content": "Danbo"
    }
  ]
}
```

Uploading training data for vision fine-tuning follows the [same process described here](/docs/guides/supervised-fine-tuning).

Image data requirements
-----------------------

#### Size

*   Your training file can contain a maximum of 50,000 examples that contain images (not including text examples).
*   Each example can have at most 10 images.
*   Each image can be at most 10 MB.

#### Format

*   Images must be JPEG, PNG, or WEBP format.
*   Your images must be in the RGB or RGBA image mode.
*   You cannot include images as output from messages with the `assistant` role.

#### Content moderation policy

We scan your images before training to ensure that they comply with our usage policy. This may introduce latency in file validation before fine-tuning begins.

Images containing the following will be excluded from your dataset and not used for training:

*   People
*   Faces
*   Children
*   CAPTCHAs

#### What to do if your images get skipped

Your images can get skipped during training for the following reasons:

*   **contains CAPTCHAs**, **contains people**, **contains faces**, **contains children**
    *   Remove the image. For now, we cannot fine-tune models with images containing these entities.
*   **inaccessible URL**
    *   Ensure that the image URL is publicly accessible.
*   **image too large**
    *   Please ensure that your images fall within our [dataset size limits](#size).
*   **invalid image format**
    *   Please ensure that your images fall within our [dataset format](#format).

Best practices
--------------

#### Reducing training cost

If you set the `detail` parameter for an image to `low`, the image is resized to 512 by 512 pixels and is only represented by 85 tokens regardless of its size. This will reduce the cost of training. [See here for more information.](/docs/guides/vision#low-or-high-fidelity-image-understanding)

```json
{
  "type": "image_url",
  "image_url": {
    "url": "https://upload.wikimedia.org/wikipedia/commons/3/36/Danbo_Cheese.jpg",
    "detail": "low"
  }
}
```

#### Control image quality

To control the fidelity of image understanding, set the `detail` parameter of `image_url` to `low`, `high`, or `auto` for each image. This will also affect the number of tokens per image that the model sees during training time, and will affect the cost of training. [See here for more information](/docs/guides/vision#low-or-high-fidelity-image-understanding).

Next steps
----------

Now that you know the basics of vision fine-tuning, explore these other methods as well.

[

Supervised fine-tuning

Fine-tune a model by providing correct outputs for sample inputs.

](/docs/guides/supervised-fine-tuning)[

Direct preference optimization

Fine-tune a model using direct preference optimization (DPO).

](/docs/guides/direct-preference-optimization)[

Reinforcement fine-tuning

Fine-tune a reasoning model by grading its outputs.

](/docs/guides/reinforcement-fine-tuning)