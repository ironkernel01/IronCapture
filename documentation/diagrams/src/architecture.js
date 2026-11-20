// Run with node from the sibling IronForge workspace or pass its path as argv[2].
const fs = require("node:fs");
const path = require("node:path");
const forge = path.resolve(process.argv[2] || path.join(__dirname, "../../../../IronForge"));
const { newDeck, helpers } = require(path.join(forge, "documentation/drawings/lib/engslides.js"));

async function main() {
  const deck = newDeck("IronCapture camera and DDR interfaces", "IronKernel");
  const { box, container, frame, label, notes, wire } = helpers(deck);
  const slide = deck.addSlide();
  frame(slide);

  container(slide, 2.55, 0.91, 8.18, 4.73, "IronCapture");
  box(slide, 0.68, 2.00, 1.34, 0.80, "Camera", ["Two CSI-2 lanes", "RAW10"]);
  box(slide, 2.90, 2.00, 1.70, 0.80, "CSI-2 receiver", ["Lane and packet checks", "RAW10 unpack"]);
  box(slide, 5.04, 2.00, 1.72, 0.80, "Bayer pipeline", ["Demosaic and color", "RGB to YUYV"]);
  box(slide, 7.50, 2.00, 2.02, 0.80, "Source selector", ["Sensor or pattern", "Two pixels per word"]);
  box(slide, 7.50, 1.28, 2.02, 0.40, "Pattern generator");
  box(slide, 7.50, 4.21, 2.02, 0.80, "Frame writer", ["Destination address", "Burst assembly"]);
  box(slide, 11.29, 2.00, 1.35, 0.80, "FPGA logic", ["Stream interface"]);
  box(slide, 11.29, 4.21, 1.35, 0.80, "DDR", ["YUYV frames"]);
  box(slide, 0.68, 4.21, 1.34, 0.80, "Host", ["MMIO driver"]);
  box(slide, 2.90, 4.21, 1.70, 0.80, "Control and status", ["Mode and source", "Buffer submission"]);

  wire(slide, 2.02, 2.40, 2.90, 2.40);
  wire(slide, 4.60, 2.40, 5.04, 2.40);
  wire(slide, 6.76, 2.40, 7.50, 2.40);
  wire(slide, 8.51, 1.68, 8.51, 2.00);
  wire(slide, 9.52, 2.40, 11.29, 2.40);
  label(slide, 9.57, 2.16, 1.05, "AXI4-Stream", 7.5, "center");
  wire(slide, 8.51, 2.80, 8.51, 4.21);
  wire(slide, 9.52, 4.61, 11.29, 4.61);
  label(slide, 9.57, 4.37, 1.05, "AXI4 writes", 7.5, "center");
  wire(slide, 2.02, 4.61, 2.90, 4.61, { start: true, dash: "dash" });
  label(slide, 2.02, 4.37, 0.52, "AXI4-Lite", 7.5, "center");
  wire(slide, 4.60, 4.61, 7.50, 4.61, { dash: "dash" });
  label(slide, 5.05, 4.37, 1.95, "Buffer address and capture control", 7.5, "center");

  notes(slide, 0.68, 5.98, 12.0, 0.95, [
    "Two integration options are shown. The streaming receiver feeds FPGA logic directly. The memory top connects the same stream to its AXI4 frame writer.",
    "The frame writer accepts one destination buffer at a time. A completion interrupt tells the host when the AXI write responses have returned.",
    "Both sources produce packed YUYV. The internal pattern exercises the downstream interface independently of the camera."
  ]);

  const assets = path.resolve(__dirname, "../../assets");
  fs.mkdirSync(assets, { recursive: true });
  await deck.writeFile({ fileName: path.join(assets, "architecture.pptx") });
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
