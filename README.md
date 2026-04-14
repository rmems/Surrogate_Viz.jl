# Surrogate_Viz.jl

A Julia-based research project focused on discovering new mathematical equation algorithms for Spiking Neural Network (SNN) quantization and developing novel training algorithms for Spikenaut, a pure SNN model.

## Overview

This repository serves as the foundation for exploring mathematical formulations in SNN quantization, with the ultimate goal of creating efficient training algorithms for Spikenaut. The project leverages latent data generated from a 508-neuron brain model to drive discoveries in neural network quantization techniques.

## Current Goals

### Teaching LLMs SNN Language
The primary focus is to instruct Large Language Models in the language of Spiking Neural Networks. This involves:

- Developing quantization strategies for SNN architectures
- Creating instructional datasets that bridge LLM and SNN paradigms
- Experimenting with various model architectures to understand SNN language acquisition

### Target Models
Current experimentation focuses on the following instructor models:

- **OLMoE-1B-7B-Instructor** - Mixture of Experts architecture
- **LFM2-8B-A1B** - Advanced language model
- **Phi-3-mini-4k-instruct** - Compact instruction-tuned model
- **Falcon3-7B-Instruct** - Open-source instruction following model

## Research Methodology

### 508-Neuron Brain Model
- Utilizes a 508-neuron brain architecture to generate latent data during quantization experiments
- This latent data serves as the foundation for discovering new mathematical equations
- The brain model provides biological inspiration for artificial quantization algorithms

### Mathematical Discovery
- Analyzing patterns in latent data to formulate new quantization equations
- Developing surrogate visualization techniques to understand quantization dynamics
- Iterative refinement of mathematical models based on experimental results

## Future Work

### Grand Quantization of Grok-1
- Apply discovered quantization algorithms to Grok-1 (sourced from xai-org HuggingFace)
- Scale quantization techniques to larger model architectures
- Validate mathematical formulations on state-of-the-art models

### Spikenaut Training Algorithm
- Develop a complete training algorithm for pure SNN models
- Integrate discovered quantization methods into the training pipeline
- Create efficient SNN-specific optimization strategies

## Project Structure

```
Surrogate_Viz.jl/
├── SAAQ_discovery.jl    # SNN Algorithm and Quantization discovery experiments
└── README.md             # Project documentation
```

## Installation

```julia
# Add the package (when published)
using Pkg
Pkg.add("Surrogate_Viz")
```

For development:
```julia
using Pkg
Pkg.develop(path="path/to/Surrogate_Viz.jl")
```

## Usage

```julia
using Surrogate_Viz

# Example usage will be added as the project develops
```

## Contributing

This is an active research project. Contributions and collaborations are welcome as the mathematical foundations develop.

## License

[License to be determined]

## Acknowledgments

- xai-org for Grok-1 model access via HuggingFace
- The open-source community for the target LLM models
- Research community in SNN and quantization fields
