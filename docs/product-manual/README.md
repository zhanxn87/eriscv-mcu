# eRISCV MCU Family Product Manual

This directory is the English-only product-manual review set for the eRISCV
MCU family. It is intentionally separate from engineering plans, verification
issue logs, and dated evidence snapshots.

## Current state

The HTML set establishes the family guide, three preliminary product
datasheets, architecture, software/SDK, controlled performance evidence,
verification, FPGA evaluation, and the board/JTAG evidence plan. It is not a
release document or an electrical/package specification.

## Authoring rules

- Write all product-manual content in English.
- Use **shall** only for a released normative contract; use **may** for an
  option and **not supported** for an explicit exclusion.
- Do not infer performance, package, electrical, availability, certification,
  or lifecycle data from RTL or simulation evidence.
- Do not copy a register map, IRQ allocation, address map, ISA declaration, or
  feature status by hand into multiple documents. The Architecture chapter owns
  the current family-level ISA/ABI, address-map, and PLIC-allocation summary.
- Each figure needs a stable figure ID, English title, source asset, and
  revision. Architecture diagrams use SVG; timing diagrams use WaveDrom source
  and generated SVG; screenshots are evidence only.
- Keep implementation evidence and errata in their dedicated documents. A
  product page may link to them but must not convert a regression result into a
  commercial claim.

## Structure

```text
index.html                     Family product guide
architecture.html              Architecture and programming model
software.html                  Toolchain, BSP, and RTOS guide
performance.html               Controlled benchmark evidence
verification.html              Verification and release-boundary guide
products/                      Per-product preliminary HTML datasheets
fpga-evaluation.html           Routed VCU108 timing and resource summary
board-jtag-debug.html          Board and JTAG physical-evidence guide
assets/site.css                Shared responsive and print styling
assets/site.js                 Navigation behavior
assets/diagrams/               Versioned diagram sources and SVG output
```

## Navigation check

After changing a manual page, run:

```bash
python3 scripts/check_navigation.py
```

Do not create a second family-level address-map or IRQ-allocation page. The
engineering contracts and dated evidence are indexed from `../README.md`.
