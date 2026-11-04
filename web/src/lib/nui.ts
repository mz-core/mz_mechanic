const RESOURCE_NAME = /^[A-Za-z0-9_-]+$/
const CALLBACK_NAME = /^[A-Za-z0-9:_-]+$/

export function currentResourceName() {
  const parent = (window as Window & { GetParentResourceName?: () => string }).GetParentResourceName
  if (typeof parent !== "function") throw new Error("NUI indisponível fora do FiveM")
  return parent()
}

export async function postNui<TResult>(callbackName: string, payload: unknown, timeoutMs = 8_000, signal?: AbortSignal): Promise<TResult> {
  const resourceName = currentResourceName()
  if (!RESOURCE_NAME.test(resourceName) || !CALLBACK_NAME.test(callbackName)) throw new Error("Contrato NUI inválido")
  const controller = new AbortController()
  const abort = () => controller.abort()
  if (signal?.aborted) controller.abort()
  else signal?.addEventListener("abort", abort, { once: true })
  const timeout = window.setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(`https://${resourceName}/${callbackName}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: controller.signal,
    })
    if (!response.ok) throw new Error(`NUI HTTP ${response.status}`)
    return (await response.json()) as TResult
  } finally {
    window.clearTimeout(timeout)
    signal?.removeEventListener("abort", abort)
  }
}

