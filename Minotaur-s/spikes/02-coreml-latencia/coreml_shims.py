# -*- coding: utf-8 -*-
"""
Shim de conversão: registra o op `new_ones` no frontend Torch do coremltools.

Motivo (Spike 2): o coremltools 9.0 registra `new_full` e `new_zeros`, mas
NÃO registra `new_ones` — uma lacuna do conversor exposta ao usar um torch
mais novo que o testado (2.13 vs 2.7 máx. testado). `new_ones` é apenas
`new_full` com valor 1, então o shim reaproveita o mesmo helper interno.

IMPORTANTE: isto NÃO altera a arquitetura de nenhum modelo. É só um tradutor
de um op trivial de criação de tensor, preenchendo uma lacuna do coremltools.
Aprovado explicitamente pelo usuário (passo 3 do Spike 2).

Basta `import coreml_shims` ANTES de chamar ct.convert(...).
"""
from coremltools.converters.mil.mil import Builder as mb
from coremltools.converters.mil.mil import types
from coremltools.converters.mil.frontend.torch.ops import _get_inputs, _make_fill_op
from coremltools.converters.mil.frontend.torch.torch_op_registry import (
    register_torch_op,
)


_fired = set()


def _note(name):
    """Avisa (uma vez) quando um shim é de fato acionado durante a conversão.
    Serve para saber se o toolchain suportado (torch 2.7) ainda precisa deles."""
    if name not in _fired:
        _fired.add(name)
        print(f"[coreml_shims] shim '{name}' ACIONADO na conversão", flush=True)


@register_torch_op
def new_ones(context, node):
    # tensor.new_ones(size, dtype=...) -> tensor de 1s com o shape `size`.
    _note("new_ones")
    inputs = _get_inputs(context, node)
    size = inputs[1]
    result = _make_fill_op(size, 1, node.name)
    context.add(result)


@register_torch_op(torch_alias=["and"], override=True)
def bitwise_and(context, node):
    # O coremltools 9.0 só aceita bitwise_and entre bools; o transformers/torch
    # 2.13 emite bitwise_and entre int e bool na preparação da máscara de atenção.
    # Mesma classe de incompatibilidade de versão do `new_ones` — casta ambos os
    # operandos para bool e faz logical_and. NÃO altera a arquitetura do modelo.
    _note("bitwise_and")
    inputs = _get_inputs(context, node)
    x, y = inputs[0], inputs[1]
    if not types.is_bool(x.dtype):
        x = mb.cast(x=x, dtype="bool")
    if not types.is_bool(y.dtype):
        y = mb.cast(x=y, dtype="bool")
    context.add(mb.logical_and(x=x, y=y, name=node.name))
