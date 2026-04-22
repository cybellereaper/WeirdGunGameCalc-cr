import init, { evaluate_expression } from "./pkg/wgg_webasm_calc.js";

const expressionInput = document.getElementById("expression");
const resultOutput = document.getElementById("result");
const errorOutput = document.getElementById("error");
const calculateBtn = document.getElementById("calculate");
const clearBtn = document.getElementById("clear");

function setError(message) {
  errorOutput.textContent = message;
}

function clearError() {
  setError("");
}

function setResult(value) {
  resultOutput.textContent = Number.isInteger(value) ? value.toString() : value.toFixed(6).replace(/\.0+$/, "").replace(/(\.\d*?)0+$/, "$1");
}

function calculate() {
  clearError();
  try {
    const expression = expressionInput.value;
    const result = evaluate_expression(expression);
    setResult(result);
  } catch (error) {
    resultOutput.textContent = "—";
    setError(error instanceof Error ? error.message : String(error));
  }
}

function clearAll() {
  expressionInput.value = "";
  resultOutput.textContent = "—";
  clearError();
  expressionInput.focus();
}

async function bootstrap() {
  try {
    await init();
  } catch (error) {
    setError(`Failed to load WebAssembly module: ${error}`);
    calculateBtn.disabled = true;
    return;
  }

  calculateBtn.addEventListener("click", calculate);
  clearBtn.addEventListener("click", clearAll);
  expressionInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      calculate();
    }
  });
}

bootstrap();
