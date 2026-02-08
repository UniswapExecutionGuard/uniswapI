import { BrowserProvider, Contract } from "https://cdn.jsdelivr.net/npm/ethers@6.13.4/+esm";

const POLICY_ABI = [
  "function setPolicy(address trader,uint256 maxSwapAbs,uint256 cooldownSeconds)",
  "function setPolicyForENS(string name,uint256 maxSwapAbs,uint256 cooldownSeconds)",
  "function clearPolicy(address trader)",
  "function resolveENS(string name) view returns (address)",
  "function getPolicy(address trader) view returns (uint256 maxSwapAbs,uint256 cooldownSeconds,bool exists)",
  "event PolicySet(address indexed trader,uint256 maxSwapAbs,uint256 cooldownSeconds)",
  "event PolicyCleared(address indexed trader)"
];

const HOOK_ABI = [
  "function setDefaults(uint256 defaultMaxSwapAbs,uint256 defaultCooldownSeconds)",
  "event DefaultsUpdated(uint256 defaultMaxSwapAbs,uint256 defaultCooldownSeconds)",
  "event SwapAllowed(address indexed trader,int256 amountSpecified,uint256 maxSwapAbs,uint256 cooldownSeconds)",
  "event SwapBlocked(address indexed trader,uint8 reason,int256 amountSpecified)"
];

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const DEFAULT_MAX_SWAP_ABS = "1000000000000000000";
const DEFAULT_COOLDOWN_SECONDS = "60";
const UI_CONFIG = window.DEMO_UI_CONFIG || {};

const el = (id) => document.getElementById(id);
const txLog = el("txLog");
const eventsOut = el("eventsOut");
const walletState = el("walletState");

let browserProvider;
let signer;
let connectedAddress = "";

function appendLog(line) {
  const ts = new Date().toLocaleTimeString();
  txLog.textContent = txLog.textContent === "-" ? `[${ts}] ${line}` : `${txLog.textContent}\n[${ts}] ${line}`;
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim() !== "") return value.trim();
  }
  return "";
}

function setIfEmpty(id, value) {
  if (!value) return;
  const input = el(id);
  if (!input.value.trim()) input.value = value;
}

function getAddresses() {
  return {
    registry: el("registryAddress").value.trim(),
    hook: el("hookAddress").value.trim()
  };
}

function getRegistryContract(withSigner = true) {
  const { registry } = getAddresses();
  if (!registry) throw new Error("Set PolicyRegistry address first");
  const providerOrSigner = withSigner ? signer : browserProvider;
  return new Contract(registry, POLICY_ABI, providerOrSigner);
}

function getHookContract(withSigner = true) {
  const { hook } = getAddresses();
  if (!hook) throw new Error("Set UniswapExeGuard address first");
  const providerOrSigner = withSigner ? signer : browserProvider;
  return new Contract(hook, HOOK_ABI, providerOrSigner);
}

function saveAddresses() {
  localStorage.setItem("ueg_registry", el("registryAddress").value.trim());
  localStorage.setItem("ueg_hook", el("hookAddress").value.trim());
  appendLog("Saved contract addresses locally");
}

function loadAddresses() {
  el("registryAddress").value = localStorage.getItem("ueg_registry") || "";
  el("hookAddress").value = localStorage.getItem("ueg_hook") || "";
  applyConfigDefaults();
}

function applyConfigDefaults() {
  setIfEmpty("registryAddress", UI_CONFIG.POLICY_REGISTRY);
  setIfEmpty("hookAddress", UI_CONFIG.UNISWAP_EXE_GUARD);

  const maxSwap = firstNonEmpty(UI_CONFIG.MAX_SWAP_ABS, UI_CONFIG.DEFAULT_MAX_SWAP_ABS, DEFAULT_MAX_SWAP_ABS);
  const cooldown = firstNonEmpty(UI_CONFIG.COOLDOWN_SECONDS, UI_CONFIG.DEFAULT_COOLDOWN_SECONDS, DEFAULT_COOLDOWN_SECONDS);
  setIfEmpty("setMaxSwap", maxSwap);
  setIfEmpty("ensMaxSwap", maxSwap);
  setIfEmpty("defaultMaxSwap", maxSwap);
  setIfEmpty("setCooldown", cooldown);
  setIfEmpty("ensCooldown", cooldown);
  setIfEmpty("defaultCooldown", cooldown);

  const trader = firstNonEmpty(UI_CONFIG.TRADER);
  setIfEmpty("readTrader", trader);
  setIfEmpty("setTrader", trader);
  setIfEmpty("clearTrader", trader);

  const ensName = firstNonEmpty(UI_CONFIG.ENS_NAME);
  setIfEmpty("readEnsName", ensName);
  setIfEmpty("ensName", ensName);
  setIfEmpty("clearEnsName", ensName);
}

async function connectWallet() {
  if (!window.ethereum) throw new Error("No injected wallet found (MetaMask/Rabby)");
  browserProvider = new BrowserProvider(window.ethereum);
  await browserProvider.send("eth_requestAccounts", []);
  signer = await browserProvider.getSigner();
  connectedAddress = await signer.getAddress();
  const network = await browserProvider.getNetwork();
  walletState.textContent = `${connectedAddress} | chainId=${network.chainId}`;
  appendLog(`Connected wallet ${connectedAddress}`);
}

async function sendTx(label, fn) {
  if (!signer) throw new Error("Connect wallet first");
  const tx = await fn();
  appendLog(`${label} tx submitted: ${tx.hash}`);
  const rcpt = await tx.wait();
  appendLog(`${label} confirmed in block ${rcpt.blockNumber}`);
}

async function readPolicy() {
  const trader = el("readTrader").value.trim();
  if (!trader) throw new Error("Trader address is required");
  const registry = getRegistryContract(false);
  const [maxSwapAbs, cooldownSeconds, exists] = await registry.getPolicy(trader);
  el("policyOut").textContent = JSON.stringify(
    {
      trader,
      maxSwapAbs: maxSwapAbs.toString(),
      cooldownSeconds: cooldownSeconds.toString(),
      exists
    },
    null,
    2
  );
}

async function resolveEnsFromRegistry(ensName) {
  const registry = getRegistryContract(false);
  const trader = await registry.resolveENS(ensName);
  if (trader.toLowerCase() === ZERO_ADDRESS) throw new Error(`ENS ${ensName} unresolved in PolicyRegistry`);
  return trader;
}

async function readPolicyByEns() {
  if (!browserProvider) throw new Error("Connect wallet first");
  const ensName = el("readEnsName").value.trim();
  if (!ensName) throw new Error("ENS name is required");
  const trader = await resolveEnsFromRegistry(ensName);

  const registry = getRegistryContract(false);
  const [maxSwapAbs, cooldownSeconds, exists] = await registry.getPolicy(trader);
  el("ensPolicyOut").textContent = JSON.stringify(
    {
      ensName,
      trader,
      maxSwapAbs: maxSwapAbs.toString(),
      cooldownSeconds: cooldownSeconds.toString(),
      exists
    },
    null,
    2
  );
}

async function clearPolicyByEns() {
  if (!browserProvider) throw new Error("Connect wallet first");
  if (!signer) throw new Error("Connect wallet first");

  const ensName = el("clearEnsName").value.trim();
  if (!ensName) throw new Error("ENS name is required");
  const trader = await resolveEnsFromRegistry(ensName);

  const registry = getRegistryContract(true);
  await sendTx(`clearPolicy(${ensName} -> ${trader})`, () => registry.clearPolicy(trader));
}

async function loadEvents() {
  const lookback = Number(el("blockLookback").value || "2000");
  const registry = getRegistryContract(false);
  const hook = getHookContract(false);
  const latest = await browserProvider.getBlockNumber();
  const from = Math.max(0, latest - lookback);

  const out = [];
  const [policySet, policyCleared, defaultsUpdated, swapAllowed, swapBlocked] = await Promise.all([
    registry.queryFilter(registry.filters.PolicySet(), from, latest),
    registry.queryFilter(registry.filters.PolicyCleared(), from, latest),
    hook.queryFilter(hook.filters.DefaultsUpdated(), from, latest),
    hook.queryFilter(hook.filters.SwapAllowed(), from, latest),
    hook.queryFilter(hook.filters.SwapBlocked(), from, latest)
  ]);

  policySet.forEach((e) => out.push({ kind: "PolicySet", block: e.blockNumber, args: e.args }));
  policyCleared.forEach((e) => out.push({ kind: "PolicyCleared", block: e.blockNumber, args: e.args }));
  defaultsUpdated.forEach((e) => out.push({ kind: "DefaultsUpdated", block: e.blockNumber, args: e.args }));
  swapAllowed.forEach((e) => out.push({ kind: "SwapAllowed", block: e.blockNumber, args: e.args }));
  swapBlocked.forEach((e) => out.push({ kind: "SwapBlocked", block: e.blockNumber, args: e.args }));

  out.sort((a, b) => a.block - b.block);
  eventsOut.textContent = out.length
    ? JSON.stringify(
        out.map((e) => ({
          kind: e.kind,
          block: e.block,
          args: Array.from(e.args || []).map((x) => (typeof x === "bigint" ? x.toString() : x))
        })),
        null,
        2
      )
    : "No events in range";
}

async function onClick(handler) {
  try {
    await handler();
  } catch (err) {
    appendLog(`ERROR: ${err.message || String(err)}`);
  }
}

el("connectBtn").addEventListener("click", () => onClick(connectWallet));
el("saveContractsBtn").addEventListener("click", () => onClick(async () => saveAddresses()));
el("readPolicyBtn").addEventListener("click", () => onClick(readPolicy));
el("readEnsPolicyBtn").addEventListener("click", () => onClick(readPolicyByEns));
el("loadEventsBtn").addEventListener("click", () => onClick(loadEvents));

el("setPolicyBtn").addEventListener("click", () =>
  onClick(async () => {
    const registry = getRegistryContract(true);
    const trader = el("setTrader").value.trim();
    const maxSwap = el("setMaxSwap").value.trim();
    const cooldown = el("setCooldown").value.trim();
    await sendTx("setPolicy", () => registry.setPolicy(trader, maxSwap, cooldown));
  })
);

el("setEnsPolicyBtn").addEventListener("click", () =>
  onClick(async () => {
    const registry = getRegistryContract(true);
    const name = el("ensName").value.trim();
    const maxSwap = el("ensMaxSwap").value.trim();
    const cooldown = el("ensCooldown").value.trim();
    await sendTx("setPolicyForENS", () => registry.setPolicyForENS(name, maxSwap, cooldown));
  })
);

el("clearPolicyBtn").addEventListener("click", () =>
  onClick(async () => {
    const registry = getRegistryContract(true);
    const trader = el("clearTrader").value.trim();
    await sendTx("clearPolicy", () => registry.clearPolicy(trader));
  })
);
el("clearEnsPolicyBtn").addEventListener("click", () => onClick(clearPolicyByEns));

el("setDefaultsBtn").addEventListener("click", () =>
  onClick(async () => {
    const hook = getHookContract(true);
    const maxSwap = el("defaultMaxSwap").value.trim();
    const cooldown = el("defaultCooldown").value.trim();
    await sendTx("setDefaults", () => hook.setDefaults(maxSwap, cooldown));
  })
);

loadAddresses();
