import { AbiCoder, BrowserProvider, Contract, MaxUint256, keccak256 } from "https://cdn.jsdelivr.net/npm/ethers@6.13.4/+esm";

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
  "function defaultMaxSwapAbs() view returns (uint256)",
  "function defaultCooldownSeconds() view returns (uint256)",
  "function lastSwapTimestampByPool(address trader,bytes32 poolId) view returns (uint256)",
  "event DefaultsUpdated(uint256 defaultMaxSwapAbs,uint256 defaultCooldownSeconds)",
  "event SwapAllowed(address indexed trader,int256 amountSpecified,uint256 maxSwapAbs,uint256 cooldownSeconds)",
  "event SwapBlocked(address indexed trader,uint8 reason,int256 amountSpecified)"
];

const SWAP_ROUTER_ABI = [
  "function swap((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) key,(bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96) params,(bool takeClaims,bool settleUsingBurn) testSettings,bytes hookData) payable returns (int256 delta)"
];

const ERC20_ABI = [
  "function approve(address spender,uint256 amount) returns (bool)"
];

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const DEFAULT_MAX_SWAP_ABS = "1000000000000000000";
const DEFAULT_COOLDOWN_SECONDS = "60";
const DEFAULT_SWAP_FEE = "3000";
const DEFAULT_TICK_SPACING = "60";
const DEFAULT_ALLOWED_INPUT = "100000000000000000";
const DEFAULT_BLOCKED_INPUT = "2000000000000000000";
const MIN_SQRT_PRICE_PLUS_ONE = 4295128740n;
const UI_CONFIG = window.DEMO_UI_CONFIG || {};
const abiCoder = AbiCoder.defaultAbiCoder();

const el = (id) => document.getElementById(id);
const txLog = el("txLog");
const eventsOut = el("eventsOut");
const walletState = el("walletState");
const swapOut = el("swapOut");
const stateOut = el("stateOut");

let browserProvider;
let signer;
let connectedAddress = "";
let stateSnapshot = null;

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

function setFromConfig(id, ...values) {
  const value = firstNonEmpty(...values);
  if (!value) return;
  el(id).value = value;
}

function getAddresses() {
  return {
    registry: el("registryAddress").value.trim(),
    hook: el("hookAddress").value.trim()
  };
}

function getSwapInputs() {
  return {
    router: el("swapRouterAddress").value.trim(),
    token0: el("swapToken0").value.trim(),
    token1: el("swapToken1").value.trim(),
    fee: el("swapFee").value.trim(),
    tickSpacing: el("swapTickSpacing").value.trim(),
    allowedInput: el("swapAllowedInput").value.trim(),
    blockedInput: el("swapBlockedInput").value.trim()
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

function getSwapRouterContract(withSigner = true) {
  const { router } = getSwapInputs();
  if (!router) throw new Error("Set PoolSwapTest address first");
  const providerOrSigner = withSigner ? signer : browserProvider;
  return new Contract(router, SWAP_ROUTER_ABI, providerOrSigner);
}

function getTokenContract(tokenAddress, withSigner = true) {
  if (!tokenAddress) throw new Error("Token address missing");
  const providerOrSigner = withSigner ? signer : browserProvider;
  return new Contract(tokenAddress, ERC20_ABI, providerOrSigner);
}

function saveAddresses() {
  localStorage.setItem("ueg_registry", el("registryAddress").value.trim());
  localStorage.setItem("ueg_hook", el("hookAddress").value.trim());
  localStorage.setItem("ueg_swap_router", el("swapRouterAddress").value.trim());
  localStorage.setItem("ueg_swap_token0", el("swapToken0").value.trim());
  localStorage.setItem("ueg_swap_token1", el("swapToken1").value.trim());
  localStorage.setItem("ueg_swap_fee", el("swapFee").value.trim());
  localStorage.setItem("ueg_swap_tick_spacing", el("swapTickSpacing").value.trim());
  localStorage.setItem("ueg_swap_allowed_input", el("swapAllowedInput").value.trim());
  localStorage.setItem("ueg_swap_blocked_input", el("swapBlockedInput").value.trim());
  localStorage.setItem("ueg_state_trader", el("stateTrader").value.trim());
  localStorage.setItem("ueg_state_test_amount", el("stateTestAmount").value.trim());
  appendLog("Saved contract addresses locally");
}

function loadAddresses() {
  el("registryAddress").value = localStorage.getItem("ueg_registry") || "";
  el("hookAddress").value = localStorage.getItem("ueg_hook") || "";
  el("swapRouterAddress").value = localStorage.getItem("ueg_swap_router") || "";
  el("swapToken0").value = localStorage.getItem("ueg_swap_token0") || "";
  el("swapToken1").value = localStorage.getItem("ueg_swap_token1") || "";
  el("swapFee").value = localStorage.getItem("ueg_swap_fee") || "";
  el("swapTickSpacing").value = localStorage.getItem("ueg_swap_tick_spacing") || "";
  el("swapAllowedInput").value = localStorage.getItem("ueg_swap_allowed_input") || "";
  el("swapBlockedInput").value = localStorage.getItem("ueg_swap_blocked_input") || "";
  el("stateTrader").value = localStorage.getItem("ueg_state_trader") || "";
  el("stateTestAmount").value = localStorage.getItem("ueg_state_test_amount") || "";
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
  setIfEmpty("stateTrader", trader);

  const ensName = firstNonEmpty(UI_CONFIG.ENS_NAME);
  setIfEmpty("readEnsName", ensName);
  setIfEmpty("ensName", ensName);
  setIfEmpty("clearEnsName", ensName);

  // For live demos, prefer current .env-backed values over stale localStorage values.
  setFromConfig("swapRouterAddress", UI_CONFIG.LIVE_SWAP_ROUTER);
  setFromConfig("swapToken0", UI_CONFIG.LIVE_TOKEN0);
  setFromConfig("swapToken1", UI_CONFIG.LIVE_TOKEN1);
  setFromConfig("swapFee", UI_CONFIG.LIVE_POOL_FEE, DEFAULT_SWAP_FEE);
  setFromConfig("swapTickSpacing", UI_CONFIG.LIVE_TICK_SPACING, DEFAULT_TICK_SPACING);
  setFromConfig("swapAllowedInput", UI_CONFIG.LIVE_ALLOWED_INPUT, DEFAULT_ALLOWED_INPUT);
  setFromConfig("swapBlockedInput", UI_CONFIG.LIVE_BLOCKED_INPUT, DEFAULT_BLOCKED_INPUT);
  setFromConfig("stateTestAmount", UI_CONFIG.LIVE_ALLOWED_INPUT, DEFAULT_ALLOWED_INPUT);
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

function renderSwapResult(payload) {
  swapOut.textContent = JSON.stringify(payload, null, 2);
}

function parseError(err) {
  return (
    err?.shortMessage ||
    err?.reason ||
    err?.info?.error?.message ||
    err?.message ||
    String(err)
  );
}

function normalizeAddress(addr) {
  return addr.toLowerCase();
}

function sortAddressPair(a, b) {
  const aNorm = normalizeAddress(a);
  const bNorm = normalizeAddress(b);
  return aNorm < bNorm ? [a, b] : [b, a];
}

function buildSwapKey() {
  const { hook } = getAddresses();
  if (!hook) throw new Error("Set UniswapExeGuard address first");

  const { token0, token1, fee, tickSpacing } = getSwapInputs();
  if (!token0 || !token1) throw new Error("Set Token0 and Token1");
  if (!fee || !tickSpacing) throw new Error("Set fee and tick spacing");

  const [currency0, currency1] = sortAddressPair(token0, token1);
  return {
    currency0,
    currency1,
    fee: Number(fee),
    tickSpacing: Number(tickSpacing),
    hooks: hook
  };
}

function buildPoolIdFromInputs() {
  const key = buildSwapKey();
  const encoded = abiCoder.encode(
    ["tuple(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)"],
    [key]
  );
  return { key, poolId: keccak256(encoded) };
}

function parseBigIntInput(label, value) {
  const trimmed = value.trim();
  if (!trimmed) throw new Error(`${label} is required`);
  try {
    return BigInt(trimmed);
  } catch {
    throw new Error(`${label} must be an integer in wei`);
  }
}

function absBigInt(value) {
  return value < 0n ? -value : value;
}

function formatUnix(unixSeconds) {
  if (unixSeconds === 0n) return "0";
  return `${unixSeconds.toString()} (${new Date(Number(unixSeconds) * 1000).toLocaleString()})`;
}

function renderPolicyState(snapshot) {
  const nowLocal = BigInt(Math.floor(Date.now() / 1000));
  const remainingSeconds = snapshot.nextAllowedTimestamp > nowLocal ? snapshot.nextAllowedTimestamp - nowLocal : 0n;
  const amountAllowed = snapshot.maxSwapAbs === 0n || snapshot.testAmountAbs <= snapshot.maxSwapAbs;
  const cooldownAllowed = snapshot.cooldownSeconds === 0n || snapshot.lastSwapTimestamp === 0n || nowLocal >= snapshot.nextAllowedTimestamp;
  const allowedNow = amountAllowed && cooldownAllowed;

  stateOut.textContent = JSON.stringify(
    {
      trader: snapshot.trader,
      poolId: snapshot.poolId,
      poolKey: snapshot.key,
      policySource: snapshot.policySource,
      maxSwapAbs: snapshot.maxSwapAbs.toString(),
      cooldownSeconds: snapshot.cooldownSeconds.toString(),
      chainTimestampAtRefresh: formatUnix(snapshot.chainTimestamp),
      lastSwapTimestamp: formatUnix(snapshot.lastSwapTimestamp),
      nextAllowedTimestamp: formatUnix(snapshot.nextAllowedTimestamp),
      remainingSeconds: remainingSeconds.toString(),
      testAmountAbs: snapshot.testAmountAbs.toString(),
      amountCheck: amountAllowed ? "PASS" : "BLOCKED",
      cooldownCheck: cooldownAllowed ? "PASS" : "BLOCKED",
      allowedNow
    },
    null,
    2
  );
}

async function refreshPolicyState() {
  if (!browserProvider) throw new Error("Connect wallet first");
  const trader = el("stateTrader").value.trim();
  if (!trader) throw new Error("Trader address is required");

  const testAmountAbs = absBigInt(parseBigIntInput("Test amount", el("stateTestAmount").value));
  const registry = getRegistryContract(false);
  const hook = getHookContract(false);
  const { key, poolId } = buildPoolIdFromInputs();

  const [[policyMaxSwap, policyCooldown, hasCustomPolicy], defaultMaxSwap, defaultCooldown, lastSwap, latestBlock] = await Promise.all([
    registry.getPolicy(trader),
    hook.defaultMaxSwapAbs(),
    hook.defaultCooldownSeconds(),
    hook.lastSwapTimestampByPool(trader, poolId),
    browserProvider.getBlock("latest")
  ]);

  const maxSwapAbs = hasCustomPolicy ? policyMaxSwap : defaultMaxSwap;
  const cooldownSeconds = hasCustomPolicy ? policyCooldown : defaultCooldown;
  const nowChain = BigInt(latestBlock?.timestamp || 0);
  const nextAllowedTimestamp = lastSwap + cooldownSeconds;

  stateSnapshot = {
    trader,
    poolId,
    key,
    policySource: hasCustomPolicy ? "custom-policy" : "hook-defaults",
    maxSwapAbs,
    cooldownSeconds,
    lastSwapTimestamp: lastSwap,
    nextAllowedTimestamp,
    chainTimestamp: nowChain,
    testAmountAbs
  };
  renderPolicyState(stateSnapshot);
}

async function approveSwapTokens() {
  if (!signer) throw new Error("Connect wallet first");
  const { router, token0, token1 } = getSwapInputs();
  if (!router || !token0 || !token1) throw new Error("Set PoolSwapTest, Token0, Token1");

  const token0c = getTokenContract(token0, true);
  const token1c = getTokenContract(token1, true);

  await sendTx(`approve token0 -> ${router}`, () => token0c.approve(router, MaxUint256));
  if (normalizeAddress(token1) !== normalizeAddress(token0)) {
    await sendTx(`approve token1 -> ${router}`, () => token1c.approve(router, MaxUint256));
  }
  renderSwapResult({ approved: true, router, token0, token1 });
}

async function runSwap(expectBlocked) {
  if (!signer) throw new Error("Connect wallet first");
  const router = getSwapRouterContract(true);
  const key = buildSwapKey();
  const { allowedInput, blockedInput } = getSwapInputs();
  const amountRaw = expectBlocked ? blockedInput : allowedInput;
  if (!amountRaw) throw new Error("Swap input amount is required");

  const params = {
    zeroForOne: true,
    amountSpecified: -BigInt(amountRaw),
    sqrtPriceLimitX96: MIN_SQRT_PRICE_PLUS_ONE
  };
  const settings = { takeClaims: false, settleUsingBurn: false };

  try {
    const tx = await router.swap(key, params, settings, "0x");
    appendLog(`${expectBlocked ? "blockedSwap" : "allowedSwap"} tx submitted: ${tx.hash}`);
    const rcpt = await tx.wait();
    appendLog(`${expectBlocked ? "blockedSwap" : "allowedSwap"} confirmed in block ${rcpt.blockNumber}`);
    renderSwapResult({
      action: expectBlocked ? "blockedSwap" : "allowedSwap",
      success: true,
      txHash: tx.hash
    });
    if (expectBlocked) appendLog("WARNING: blocked swap unexpectedly succeeded");
  } catch (err) {
    const message = parseError(err);
    if (!expectBlocked) throw err;
    appendLog(`Expected blocked swap revert: ${message}`);
    renderSwapResult({
      action: "blockedSwap",
      success: false,
      expected: true,
      error: message
    });
  }
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
el("approveSwapBtn").addEventListener("click", () => onClick(approveSwapTokens));
el("runAllowedSwapBtn").addEventListener("click", () => onClick(async () => runSwap(false)));
el("runBlockedSwapBtn").addEventListener("click", () => onClick(async () => runSwap(true)));
el("refreshStateBtn").addEventListener("click", () => onClick(refreshPolicyState));

setInterval(() => {
  if (stateSnapshot) renderPolicyState(stateSnapshot);
}, 1000);

loadAddresses();
