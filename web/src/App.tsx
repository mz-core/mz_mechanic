import * as React from "react"
import {
  Activity, AlertTriangle, Armchair, ArrowLeft, BadgeCheck, Boxes, Car, ChevronRight,
  CircleDot, ClipboardCheck, ClipboardList, Eye, EyeOff, Gauge, Lightbulb, PackageCheck,
  Paintbrush, Power, RotateCcw, RotateCw, ShieldCheck, SlidersHorizontal, Undo2, Wrench,
  ZoomIn, ZoomOut,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import { postNui } from "@/lib/nui"

type CustomValue = number | boolean
type AppliedValue = CustomValue | number[]
type ViewMode = "atendimento" | "tuning"
type Service = { code: string; label: string; price: number; customization?: { code: string; field: string; slot?: number; key?: string | number; kind: string; value: AppliedValue } }
type CustomOption = { value: CustomValue; label: string; price: number }
type CustomItem = { code: string; label: string; category: string; field: string; slot?: number; kind: string; group?: string; fixedPrice?: number; applied?: CustomValue; options: CustomOption[] }
type CustomSession = { token: string; orderId: string; revision: number; netId: number; ttlSeconds: number; catalog: CustomItem[] }
type Order = {
  id: string
  workshopCode: string
  bayCode: string
  vehicle: { id: number; plate: string }
  customerCitizenId: string
  assignedMechanicCitizenId?: string
  state: string
  revision: number
  diagnostic?: { engine?: number; body?: number; dirt?: number }
  quote?: { services?: Service[]; total?: number; available?: boolean; kind?: string }
  payment?: { status?: string; amount?: number }
  application?: { status?: string; netId?: number; kind?: string; itemCount?: number }
  failureCode?: string
  cancelReason?: string
  createdAt?: string
}
type Context = {
  ok: boolean
  error?: string
  workshop: { code: string; label: string }
  user: { citizenId: string; isMechanic: boolean; onDuty: boolean; dutyMode: string; mechanicError?: string }
  vehicle?: { id: number; plate: string; model: string; netId: number; engine: number; body: number; dirt: number; bayCode?: string; inBay?: boolean }
  tuningCatalog?: CustomItem[]
  orders: Order[]
  queue: Order[]
  services: Record<string, { label: string; enabled: boolean; unavailableReason?: string }>
  capabilities: Record<string, boolean>
}
type Response = { ok: boolean; error?: string; order?: Order; pending?: boolean; requestId?: number; token?: string; orderId?: string; revision?: number; netId?: number; ttlSeconds?: number; catalog?: CustomItem[] }

const stateLabels: Record<string, string> = {
  created: "Aguardando diagnóstico",
  diagnosed: "Diagnóstico concluído",
  quoted: "Orçamento enviado",
  accepted: "Orçamento aprovado",
  in_progress: "Pagamento confirmado",
  pending_apply: "Serviço em execução",
  pending_reconciliation: "Revisão financeira",
  completed: "Serviço concluído",
  cancelled: "Ordem cancelada",
  failed: "Execução interrompida",
}

const errorLabels: Record<string, string> = {
  not_at_workshop: "Você precisa estar dentro da oficina.",
  vehicle_not_in_bay: "Posicione o veículo em uma vaga de serviço.",
  vehicle_not_stopped: "Pare o veículo completamente antes de abrir o tuning.",
  vehicle_not_out: "O veículo não está disponível no mundo para este atendimento.",
  vehicle_access_denied: "O veículo não pertence ao cliente.",
  customer_not_player_owner: "Este veículo não possui um proprietário jogador para aprovar o serviço.",
  customer_offline: "O proprietário precisa estar online e presente na oficina.",
  service_in_progress: "Este veículo já possui um atendimento em andamento.",
  vehicle_not_damaged: "Este veículo não precisa de reparo estrutural.",
  payment_failed: "A cobrança foi recusada.",
  payment_receipt_unavailable: "A cobrança precisa de conferência no ledger.",
  not_mechanic: "Seu personagem não possui vínculo de mecânico.",
  missing_permission: "Seu cargo não possui a permissão mechanic.repair.basic.",
  not_on_duty: "Entre em serviço antes de operar uma ordem.",
  invalid_vehicle: "O veículo selecionado não é válido para este atendimento.",
  invalid_net_id: "O veículo selecionado não está mais disponível.",
  vehicle_not_found: "O veículo selecionado não foi encontrado.",
  vehicle_not_registered: "Este veículo não está registrado no domínio de veículos.",
  vehicle_plate_unavailable: "Não foi possível identificar a placa do veículo.",
  routing_bucket_mismatch: "O veículo está em outra instância do jogo.",
  too_far_from_vehicle: "Permaneça próximo ao veículo para continuar.",
  schema_not_installed: "O banco da oficina ainda não foi instalado.",
  vehicle_locked: "Já existe uma ordem ativa para este veículo.",
  not_enough_money: "Saldo insuficiente para concluir o pagamento.",
  customer_not_present: "O cliente precisa permanecer próximo ao veículo.",
  apply_not_confirmed: "A execução não foi concluída; nenhuma cobrança foi feita.",
  pending_reconciliation: "A ordem foi protegida para revisão financeira.",
  rate_limited: "Aguarde um instante antes de tentar novamente.",
  server_unavailable: "A oficina não respondeu. Tente novamente.",
  context_timeout: "A oficina demorou para responder. Tente novamente.",
  preview_not_authorized: "A sessão de preview não é mais válida.",
  preview_expired: "O tempo de inspeção terminou. Abra a customização novamente.",
  no_supported_customization: "Este veículo não possui opções nos grupos habilitados.",
  unsupported_customization_option: "Esta opção não existe neste modelo.",
  empty_customization_quote: "Selecione pelo menos uma alteração com valor.",
}

const sessionErrors = new Set(["session_not_ready", "session_not_found", "character_not_active", "player_not_loaded"])
const authorizationErrors = new Set(["missing_permission", "not_on_duty", "not_mechanic"])
const vehicleErrors = new Set(["invalid_vehicle", "invalid_net_id", "vehicle_not_found", "vehicle_not_registered", "vehicle_plate_unavailable", "vehicle_identity_mismatch", "vehicle_access_denied", "routing_bucket_mismatch", "too_far_from_vehicle", "vehicle_not_in_bay", "vehicle_not_stopped", "vehicle_not_out"])
const query = new URLSearchParams(window.location.search)
const isPreview = query.get("preview") === "1"
const previewScenario = query.get("scenario") ?? "active"
const previewRole = query.get("role") === "customer" ? "customer" : "mechanic"
const previewView: ViewMode = query.get("view") === "tuning" ? "tuning" : "atendimento"
const money = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 })
const customizationCategories = [
  { id: "performance", label: "Performance", icon: Gauge },
  { id: "body", label: "Carroceria", icon: Car },
  { id: "wheels", label: "Rodas", icon: CircleDot },
  { id: "paint", label: "Pintura", icon: Paintbrush },
  { id: "lighting", label: "Iluminação", icon: Lightbulb },
  { id: "interior", label: "Interior", icon: Armchair },
  { id: "extras", label: "Extras", icon: Boxes },
]

function previewContext(): Context {
  const state = query.get("state") ?? (previewView === "tuning" ? "created" : previewScenario === "reconciliation" ? "pending_reconciliation" : previewRole === "customer" ? "quoted" : "accepted")
  const citizenId = "CID-PREVIEW"
  const order: Order = {
    id: "mzo_preview_01",
    workshopCode: "bennys",
    bayCode: "bay_1",
    vehicle: { id: 418, plate: "MZ 2048" },
    customerCitizenId: previewRole === "customer" ? citizenId : "CID-CLIENTE",
    assignedMechanicCitizenId: state === "created" && previewScenario === "queue" ? undefined : previewRole === "mechanic" ? citizenId : "CID-MECANICO",
    state,
    revision: 3,
    diagnostic: state === "created" ? undefined : { engine: 612, body: 744, dirt: 5.2 },
    quote: ["quoted", "accepted", "in_progress", "pending_apply", "pending_reconciliation", "completed"].includes(state)
      ? { total: 580, available: true, services: [{ code: "full_repair", label: "Reparo estrutural completo", price: 580 }] }
      : undefined,
    failureCode: state === "failed" ? "apply_not_confirmed" : undefined,
  }
  const empty = previewScenario === "empty"
  const queued = previewScenario === "queue"
  const noVehicle = previewScenario === "no-vehicle"
  return {
    ok: true,
    workshop: { code: "bennys", label: "Benny's Motorworks" },
    user: { citizenId, isMechanic: previewRole === "mechanic", onDuty: true, dutyMode: "org" },
    vehicle: noVehicle ? undefined : { id: 418, plate: "MZ 2048", model: "sultan", netId: 44, engine: 612, body: 744, dirt: 5.2, bayCode: "bay_1", inBay: true },
    tuningCatalog: previewView === "tuning" && !noVehicle ? previewCustomization().catalog : undefined,
    orders: empty || queued || noVehicle ? [] : [order],
    queue: queued ? [order] : [],
    services: {
      full_repair: { label: "Reparo estrutural completo", enabled: true },
      cleaning: { label: "Limpeza técnica", enabled: false, unavailableReason: "Persistência ainda não comprovada" },
    },
    capabilities: { economy: true, vehicles: true, org: true, jobsPlayable: false, customization: true },
  }
}

function previewCustomization(): CustomSession {
  return {
    token: "preview_offline_1234567890123456",
    orderId: "mzo_preview_01",
    revision: 3,
    netId: 44,
    ttlSeconds: 90,
    catalog: [
      { code: "spoilers", label: "Aerofólio", category: "body", field: "modSpoilers", slot: 0, kind: "indexed", applied: -1, options: [{ value: -1, label: "Original", price: 0 }, { value: 0, label: "Opção 01", price: 470 }, { value: 1, label: "Opção 02", price: 590 }] },
      { code: "hood", label: "Capô", category: "body", field: "modHood", slot: 7, kind: "indexed", applied: -1, options: [{ value: -1, label: "Original", price: 0 }, { value: 0, label: "Opção 01", price: 590 }, { value: 1, label: "Opção 02", price: 730 }] },
      { code: "engine", label: "Motor", category: "performance", field: "modEngine", slot: 11, kind: "indexed", applied: 0, options: [{ value: -1, label: "Original", price: 0 }, { value: 0, label: "Nível 1", price: 1850 }, { value: 1, label: "Nível 2", price: 2500 }, { value: 2, label: "Nível 3", price: 3150 }] },
      { code: "turbo", label: "Turbo", category: "performance", field: "modTurbo", slot: 18, kind: "toggle", applied: false, options: [{ value: false, label: "Desativado", price: 0 }, { value: true, label: "Ativado", price: 2800 }] },
      { code: "wheel_type", label: "Categoria das rodas", category: "wheels", field: "wheels", kind: "range", applied: 0, options: [{ value: 0, label: "Categoria 00", price: 450 }, { value: 1, label: "Categoria 01", price: 450 }] },
      { code: "primary_custom", label: "Pintura primária personalizada", category: "paint", field: "color1", kind: "rgb", group: "paint_primary", fixedPrice: 950, options: [] },
      { code: "neon_color", label: "Cor do neon", category: "lighting", field: "neonColor", kind: "rgb", applied: 0x21d4e9, fixedPrice: 600, options: [] },
      { code: "extra_00", label: "Extra 00", category: "extras", field: "extras", kind: "toggle", applied: false, options: [{ value: false, label: "Desativado", price: 0 }, { value: true, label: "Ativado", price: 220 }] },
    ],
  }
}

function requestKey() {
  return crypto.randomUUID().replaceAll("-", "_")
}

function condition(value?: number) {
  return `${Math.max(0, Math.min(100, Math.round((value ?? 0) / 10)))}%`
}

function colorHex(value: unknown) {
  const color = typeof value === "number" ? Math.max(0, Math.min(0xffffff, Math.floor(value))) : 0xffffff
  return `#${color.toString(16).padStart(6, "0")}`
}

function status(order: Order) {
  return stateLabels[order.state] ?? "Estado atualizado"
}

function stageIndex(order?: Order) {
  if (!order || order.state === "created") return order?.assignedMechanicCitizenId ? 1 : 0
  if (["diagnosed", "quoted"].includes(order.state)) return 2
  return 3
}

function safeError(reason: unknown, fallback = "Não foi possível concluir esta ação.") {
  if (reason instanceof DOMException && reason.name === "AbortError") return "A solicitação foi interrompida. Tente novamente."
  const code = reason instanceof Error ? reason.message : ""
  return errorLabels[code] ?? fallback
}

function contextErrorCopy(code: string) {
  if (sessionErrors.has(code)) return {
    title: "Personagem ainda não está pronto",
    message: "Conclua a entrada do personagem e tente abrir a oficina novamente.",
  }
  if (code === "context_timeout" || code === "server_unavailable") return {
    title: "A oficina não respondeu",
    message: "A conexão pode estar ocupada. Tente novamente uma vez ou volte ao jogo.",
  }
  if (authorizationErrors.has(code)) return {
    title: "Acesso de mecânico indisponível",
    message: errorLabels[code],
  }
  if (vehicleErrors.has(code)) return {
    title: "Veículo indisponível",
    message: errorLabels[code] ?? "Não foi possível validar o veículo para este atendimento.",
  }
  if (code === "not_at_workshop" || code === "too_far") return {
    title: "Fora da área de atendimento",
    message: errorLabels[code] ?? "Aproxime-se da oficina para continuar.",
  }
  return { title: "Não foi possível abrir a oficina", message: "Tente novamente ou volte ao jogo." }
}

function mergeOrder(context: Context, order: Order): Context {
  const replace = (items: Order[]) => items.map((item) => item.id === order.id ? order : item)
  return { ...context, orders: replace(context.orders), queue: replace(context.queue) }
}

function LoadingView() {
  return (
    <div className="loading-view" aria-label="Carregando oficina">
      <div className="loading-title"><Skeleton className="h-5 w-36" /><Skeleton className="h-4 w-24" /></div>
      <Skeleton className="h-20 w-full" />
      <Skeleton className="h-36 w-full" />
      <p>Sincronizando personagem e veículo…</p>
    </div>
  )
}

function ErrorView({ code, onRetry, onBack }: { code: string; onRetry: () => void; onBack: () => void }) {
  const copy = contextErrorCopy(code)
  return (
    <div className="context-error" role="alert">
      <span className="error-icon"><AlertTriangle aria-hidden="true" /></span>
      <p className="eyebrow">ATENDIMENTO INDISPONÍVEL</p>
      <h2>{copy.title}</h2>
      <p>{copy.message}</p>
      <div className="error-actions">
        <Button onClick={onRetry}><RotateCcw data-icon="inline-start" />Tentar novamente</Button>
        <Button variant="ghost" onClick={onBack}><ArrowLeft data-icon="inline-start" />Voltar ao jogo</Button>
      </div>
    </div>
  )
}

export function App() {
  const previewError = previewScenario === "session" ? "session_not_ready" : previewScenario === "auth" ? "not_on_duty" : null
  const [visible, setVisible] = React.useState(isPreview)
  const [viewMode, setViewMode] = React.useState<ViewMode>(previewView)
  const [context, setContext] = React.useState<Context | null>(isPreview && !previewError ? previewContext() : null)
  const [loading, setLoading] = React.useState(false)
  const [busy, setBusy] = React.useState(false)
  const [contextError, setContextError] = React.useState<string | null>(previewError)
  const [notice, setNotice] = React.useState<string | null>(null)
  const [pendingCancel, setPendingCancel] = React.useState<Order | null>(null)
  const [customization, setCustomization] = React.useState<CustomSession | null>(null)
  const [customCategory, setCustomCategory] = React.useState<string | null>(null)
  const [customCode, setCustomCode] = React.useState<string | null>(null)
  const [customSelections, setCustomSelections] = React.useState<Record<string, CustomValue>>({})
  const [inspectMode, setInspectMode] = React.useState(false)
  const activeRequest = React.useRef<string | null>(null)
  const contextTimer = React.useRef<number | null>(null)
  const refreshAbort = React.useRef<AbortController | null>(null)
  const mutationAbort = React.useRef<AbortController | null>(null)
  const panelRef = React.useRef<HTMLElement | null>(null)
  const visibleRef = React.useRef(visible)
  const pendingCancelRef = React.useRef(pendingCancel)
  const customizationRef = React.useRef(customization)
  const inspectRef = React.useRef(inspectMode)
  const viewModeRef = React.useRef<ViewMode>(viewMode)
  const entryViewRef = React.useRef<ViewMode>(previewView)
  const tuningAttempt = React.useRef<string | null>(null)

  React.useEffect(() => { visibleRef.current = visible }, [visible])
  React.useEffect(() => { pendingCancelRef.current = pendingCancel }, [pendingCancel])
  React.useEffect(() => { customizationRef.current = customization }, [customization])
  React.useEffect(() => { inspectRef.current = inspectMode }, [inspectMode])
  React.useEffect(() => { viewModeRef.current = viewMode }, [viewMode])

  const clearContextTimer = React.useCallback(() => {
    if (contextTimer.current !== null) window.clearTimeout(contextTimer.current)
    contextTimer.current = null
  }, [])

  const hide = React.useCallback(() => {
    clearContextTimer()
    activeRequest.current = null
    refreshAbort.current?.abort()
    mutationAbort.current?.abort()
    visibleRef.current = false
    pendingCancelRef.current = null
    customizationRef.current = null
    inspectRef.current = false
    viewModeRef.current = "atendimento"
    entryViewRef.current = "atendimento"
    tuningAttempt.current = null
    setVisible(false)
    setViewMode("atendimento")
    setContext(null)
    setContextError(null)
    setNotice(null)
    setPendingCancel(null)
    setCustomization(null)
    setCustomCategory(null)
    setCustomCode(null)
    setCustomSelections({})
    setInspectMode(false)
    setLoading(false)
  }, [clearContextTimer])

  const controlCamera = React.useCallback((action: "general" | "interior" | "left" | "right" | "zoomIn" | "zoomOut") => {
    if (!isPreview) void postNui<Response>("mz_mechanic:camera", { action }).catch(() => undefined)
  }, [])

  const close = React.useCallback(() => {
    if (customizationRef.current && !isPreview) {
      void postNui<Response>("mz_mechanic:cancelCustomization", {}).catch(() => undefined)
    }
    hide()
    if (!isPreview) void postNui<Response>("mz_mechanic:close", {}).catch(() => undefined)
  }, [hide])

  const beginContextLoading = React.useCallback((requestId: unknown) => {
    const id = String(requestId ?? "")
    clearContextTimer()
    activeRequest.current = id
    setContext(null)
    setContextError(null)
    setNotice(null)
    setLoading(true)
    contextTimer.current = window.setTimeout(() => {
      if (activeRequest.current !== id) return
      activeRequest.current = null
      setLoading(false)
      setContextError("context_timeout")
    }, 8_000)
  }, [clearContextTimer])

  const requestRefresh = React.useCallback(async () => {
    if (isPreview) {
      setNotice("Preview offline: nenhuma solicitação foi enviada ao servidor.")
      return
    }
    refreshAbort.current?.abort()
    const controller = new AbortController()
    refreshAbort.current = controller
    try {
      const result = await postNui<Response>("mz_mechanic:retryContext", {}, 8_000, controller.signal)
      if (!result.ok) throw new Error(result.error ?? "server_unavailable")
    } catch (reason) {
      if (controller.signal.aborted) return
      activeRequest.current = null
      clearContextTimer()
      setLoading(false)
      setContext(null)
      setContextError(reason instanceof Error ? reason.message : "server_unavailable")
    }
  }, [clearContextTimer])

  React.useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const action = event.data?.action
      if (action === "mz_mechanic:open") {
        const nextView: ViewMode = event.data?.view === "tuning" ? "tuning" : "atendimento"
        visibleRef.current = true
        viewModeRef.current = nextView
        entryViewRef.current = nextView
        tuningAttempt.current = null
        setVisible(true)
        setViewMode(nextView)
        setPendingCancel(null)
        beginContextLoading(event.data.requestId)
        window.requestAnimationFrame(() => panelRef.current?.focus())
        return
      }
      if (action === "mz_mechanic:contextLoading") {
        beginContextLoading(event.data.requestId)
        return
      }
      if (action === "mz_mechanic:context") {
        const id = String(event.data.requestId ?? "")
        if (id !== activeRequest.current) return
        activeRequest.current = null
        clearContextTimer()
        setLoading(false)
        const result = event.data.result as Context | undefined
        if (result?.ok) {
          setContext(result)
          setContextError(null)
        } else {
          setContext(null)
          setContextError(result?.error ?? "context_failed")
        }
        return
      }
      if (action === "mz_mechanic:close") {
        hide()
        return
      }
      if (action === "mz_mechanic:customizationExpired") {
        customizationRef.current = null
        setCustomization(null)
        setCustomSelections({})
        setInspectMode(false)
        controlCamera("general")
        setNotice(errorLabels.preview_expired)
        return
      }
      if (action === "mz_mechanic:orderUpdated" && event.data.order) {
        setContext((current) => current ? mergeOrder(current, event.data.order as Order) : current)
      }
    }
    const onKey = (event: KeyboardEvent) => {
      if (!visibleRef.current) return
      const cameraKeys = { ArrowLeft: "left", ArrowRight: "right", "+": "zoomIn", "=": "zoomIn", "-": "zoomOut", "1": "general", "2": "interior" } as const
      const cameraAction = cameraKeys[event.key as keyof typeof cameraKeys]
      if (inspectRef.current && cameraAction) {
        event.preventDefault()
        controlCamera(cameraAction)
        return
      }
      if (event.key !== "Escape") return
      event.preventDefault()
      if (inspectRef.current) {
        inspectRef.current = false
        setInspectMode(false)
        controlCamera("general")
      }
      else if (viewModeRef.current === "tuning" && customCategory) {
        setCustomCategory(null)
        setCustomCode(null)
      }
      else if (customizationRef.current) {
        if (!isPreview) void postNui<Response>("mz_mechanic:cancelCustomization", {}).catch(() => undefined)
        customizationRef.current = null
        setCustomization(null)
        setCustomSelections({})
        if (entryViewRef.current === "tuning") close()
        else setViewMode("atendimento")
      }
      else if (viewModeRef.current === "tuning") close()
      else if (pendingCancelRef.current) {
        pendingCancelRef.current = null
        setPendingCancel(null)
      }
      else close()
    }
    window.addEventListener("message", onMessage)
    window.addEventListener("keydown", onKey, true)
    return () => {
      window.removeEventListener("message", onMessage)
      window.removeEventListener("keydown", onKey, true)
      clearContextTimer()
      refreshAbort.current?.abort()
      mutationAbort.current?.abort()
    }
  }, [beginContextLoading, clearContextTimer, close, controlCamera, customCategory, hide])

  const mutate = React.useCallback(async (action: string, payload: object, timeout = 8_000) => {
    if (isPreview) {
      setNotice("Preview offline: nenhuma alteração foi enviada ao servidor.")
      return
    }
    mutationAbort.current?.abort()
    const controller = new AbortController()
    mutationAbort.current = controller
    setBusy(true)
    setNotice(null)
    try {
      const result = await postNui<Response>(`mz_mechanic:${action}`, payload, timeout, controller.signal)
      if (!result.ok) throw new Error(result.error ?? "operation_failed")
      await requestRefresh()
    } catch (reason) {
      if (!controller.signal.aborted) setNotice(safeError(reason))
    } finally {
      if (mutationAbort.current === controller) {
        mutationAbort.current = null
        setBusy(false)
      }
    }
  }, [requestRefresh])

  const act = React.useCallback((action: string, order: Order, reason?: string) => {
    return mutate(action, {
      orderId: order.id,
      revision: order.revision,
      requestKey: requestKey(),
      ...(reason ? { reason } : {}),
    }, action === "executeOrder" ? 15_000 : 8_000)
  }, [mutate])

  const createOrder = React.useCallback(() => {
    if (!context?.vehicle) return Promise.resolve()
    return mutate("createOrder", {
      netId: context.vehicle.netId,
      workshopCode: context.workshop.code,
      requestKey: requestKey(),
    })
  }, [context, mutate])

  const toggleDuty = React.useCallback(() => {
    if (!context) return Promise.resolve()
    return mutate("toggleDuty", { workshopCode: context.workshop.code, duty: !context.user.onDuty })
  }, [context, mutate])

  const beginCustomization = React.useCallback(async () => {
    setBusy(true)
    setNotice(null)
    try {
      const result = isPreview
        ? { ok: true, ...previewCustomization() }
        : await postNui<Response>("mz_mechanic:beginCustomization", {})
      if (!result.ok || !result.token || !result.orderId || !result.catalog?.length) {
        throw new Error(result.error ?? "no_supported_customization")
      }
      const session = result as CustomSession & { ok: true }
      viewModeRef.current = "tuning"
      setViewMode("tuning")
      customizationRef.current = session
      setCustomization(session)
      setCustomCategory(null)
      setCustomCode(null)
      setCustomSelections({})
      setInspectMode(false)
    } catch (reason) {
      setNotice(safeError(reason))
    } finally {
      setBusy(false)
    }
  }, [])

  const previewOption = React.useCallback(async (item: CustomItem, option: CustomOption) => {
    const session = customizationRef.current
    if (!session) return
    setBusy(true)
    setNotice(null)
    try {
      if (!isPreview) {
        const result = await postNui<Response>("mz_mechanic:previewCustomization", {
          orderId: session.orderId, token: session.token, code: item.code, value: option.value,
        })
        if (!result.ok) throw new Error(result.error ?? "preview_apply_failed")
        if (result.catalog?.length) {
          const refreshed = { ...session, catalog: result.catalog }
          customizationRef.current = refreshed
          setCustomization(refreshed)
        }
      }
      setCustomSelections((current) => {
        const next = { ...current }
        if (item.group) {
          for (const sibling of session.catalog) {
            if (sibling.group === item.group) delete next[sibling.code]
          }
        }
        if (option.value === item.applied) delete next[item.code]
        else next[item.code] = option.value
        return next
      })
    } catch (reason) {
      setNotice(safeError(reason))
    } finally {
      setBusy(false)
    }
  }, [])

  const cancelCustomization = React.useCallback(async () => {
    if (!isPreview) await postNui<Response>("mz_mechanic:cancelCustomization", {}).catch(() => undefined)
    customizationRef.current = null
    setCustomization(null)
    setCustomSelections({})
    setInspectMode(false)
    setNotice(null)
    if (entryViewRef.current === "tuning") close()
    else setViewMode("atendimento")
  }, [close])

  const submitCustomization = React.useCallback(async () => {
    const session = customizationRef.current
    if (!session) return
    const items = Object.entries(customSelections).map(([code, value]) => ({ code, value }))
    if (!items.length) return setNotice(errorLabels.empty_customization_quote)
    setBusy(true)
    setNotice(null)
    try {
      if (isPreview) {
        setNotice("Preview offline: orçamento não foi enviado ao servidor.")
        return
      }
      const result = await postNui<Response>("mz_mechanic:quoteCustomization", {
        orderId: session.orderId,
        revision: session.revision,
        requestKey: requestKey(),
        token: session.token,
        items,
      }, 8_000)
      if (!result.ok) throw new Error(result.error ?? "operation_failed")
      customizationRef.current = null
      setCustomization(null)
      setCustomSelections({})
      close()
    } catch (reason) {
      setNotice(safeError(reason))
    } finally {
      setBusy(false)
    }
  }, [close, customSelections])

  React.useEffect(() => {
    if (viewMode !== "tuning" || !context || customization || busy || notice) return
    if (!context.vehicle || !context.user.isMechanic || !context.user.onDuty) return
    const attempt = `${context.vehicle.id}:${context.vehicle.netId}`
    if (tuningAttempt.current === attempt) return
    tuningAttempt.current = attempt
    void beginCustomization()
  }, [beginCustomization, busy, context, customization, notice, viewMode])

  if (!visible) return <div data-testid="closed-root" aria-hidden="true" />

  const allOrders = context ? [...context.orders, ...context.queue.filter((order) => !context.orders.some((item) => item.id === order.id))] : []
  const selected = allOrders.find((order) => !["completed", "cancelled", "failed"].includes(order.state)) ?? allOrders[0]
  const stage = stageIndex(selected)
  const isCustomer = Boolean(selected && context && selected.customerCitizenId === context.user.citizenId)
  const isAssigned = Boolean(selected && context && selected.assignedMechanicCitizenId === context.user.citizenId)
  const canCancel = Boolean(selected && (isCustomer || isAssigned) && ["created", "diagnosed", "quoted", "accepted"].includes(selected.state))
  const vehicle = context?.vehicle ?? (selected ? { ...selected.vehicle, model: "veículo", netId: 0, engine: selected.diagnostic?.engine ?? 0, body: selected.diagnostic?.body ?? 0, dirt: selected.diagnostic?.dirt ?? 0 } : undefined)
  const activeCatalog = customization?.catalog ?? context?.tuningCatalog ?? []
  const customItems = activeCatalog.filter((item) => item.category === customCategory)
  const customItem = customItems.find((item) => item.code === customCode) ?? customItems[0]
  const customTotal = customization?.catalog.reduce((total, item) => {
    const selectedValue = customSelections[item.code]
    if (selectedValue === undefined) return total
    return total + (item.kind === "rgb"
      ? item.fixedPrice ?? 0
      : item.options.find((option) => option.value === selectedValue)?.price ?? 0)
  }, 0) ?? 0

  if (context && viewMode === "tuning" && (!vehicle || !context.user.isMechanic || !context.user.onDuty || !activeCatalog.length)) {
    const tuningMessage = !vehicle
      ? "Selecione um veículo em uma vaga de customização."
      : !context.user.isMechanic
        ? "Somente um mecânico autorizado pode operar a estação de tuning."
        : !context.user.onDuty
          ? "Entre em serviço antes de operar a estação de tuning."
          : "Este veículo não possui opções compatíveis no catálogo habilitado."
    return (
      <main className="mechanic-stage tuning-entry-stage" data-interface="tuning">
        <section ref={panelRef} tabIndex={-1} className="mechanic-shell tuning-entry-shell" data-testid="mechanic-panel" data-mode="tuning-entry" aria-label="Entrada da MZ Automotive">
          <header className="custom-topbar">
            <div className="custom-brand"><span>MZ // AUTOMOTIVE</span><strong>{vehicle?.model ?? "Estação de tuning"}</strong></div>
            {vehicle ? <div className="custom-vehicle-id"><span>{vehicle.plate}</span><small>{context.workshop.label}</small></div> : null}
          </header>
          <aside className="tuning-entry-card" role="status">
            <SlidersHorizontal aria-hidden="true" />
            <p className="eyebrow">ESTAÇÃO DE CUSTOMIZAÇÃO</p>
            <h1>Estação indisponível</h1>
            <p>{notice ?? tuningMessage}</p>
            <Button onClick={() => {
              viewModeRef.current = "atendimento"
              setViewMode("atendimento")
              setNotice(null)
            }}><ArrowLeft data-icon="inline-start" />Abrir atendimento</Button>
          </aside>
          <footer className="custom-help"><span>Veículo validado novamente no servidor</span><span><kbd>ESC</kbd> voltar ao jogo</span></footer>
        </section>
      </main>
    )
  }

  if (context && viewMode === "tuning" && vehicle && activeCatalog.length) {
    const browseOnly = !customization
    const selectedValue = customItem ? (customSelections[customItem.code] ?? customItem.applied) : undefined
    const categories = customizationCategories.filter((category) => activeCatalog.some((item) => item.category === category.id))
    const category = categories.find((item) => item.id === customCategory)
    return (
      <main className="mechanic-stage customization-stage" data-interface="tuning">
        <section ref={panelRef} tabIndex={-1} className={`mechanic-shell customization-shell${inspectMode ? " is-inspecting" : ""}`} data-testid="mechanic-panel" data-mode="customization" aria-label="Workspace de customização">
          {!inspectMode ? (
            <>
              <aside className="custom-vehicle-panel" aria-label="Dados do veículo">
                <div className="vehicle-panel-brand" aria-label="MZ Automotive"><span>MZ</span><small>Automotive</small></div>
                <div className="vehicle-panel-heading"><span>Veículo</span><strong>{vehicle.model}</strong></div>
                <div className="vehicle-panel-meta"><span>Placa</span><strong>{vehicle.plate}</strong></div>
                <div className="vehicle-panel-bay"><Wrench aria-hidden="true" /><span>Oficina<strong>{(selected?.bayCode ?? vehicle.bayCode ?? context.workshop.label).replace("_", " ")}</strong></span></div>
                <div className="vehicle-panel-condition">
                  <div>
                    <span>Condição do motor<strong>{condition(vehicle.engine)}</strong></span>
                    <span className="condition-meter" role="meter" aria-label={`Condição do motor: ${condition(vehicle.engine)}`} aria-valuenow={Math.round(vehicle.engine / 10)} aria-valuemin={0} aria-valuemax={100}><i style={{ width: condition(vehicle.engine) }} /></span>
                  </div>
                  <div>
                    <span>Condição da carroceria<strong>{condition(vehicle.body)}</strong></span>
                    <span className="condition-meter" role="meter" aria-label={`Condição da carroceria: ${condition(vehicle.body)}`} aria-valuenow={Math.round(vehicle.body / 10)} aria-valuemin={0} aria-valuemax={100}><i style={{ width: condition(vehicle.body) }} /></span>
                  </div>
                </div>
              </aside>

              {!category ? (
                <nav className="custom-category-menu" aria-label="Categorias de customização">
                  {categories.map((item, index) => {
                    const Icon = item.icon
                    return (
                      <button key={item.id} type="button" data-featured={index === 0} onClick={() => {
                        setCustomCategory(item.id)
                        setCustomCode(activeCatalog.find((entry) => entry.category === item.id)?.code ?? null)
                      }}>
                        <Icon aria-hidden="true" />
                        <strong>{item.label}</strong>
                      </button>
                    )
                  })}
                </nav>
              ) : (
                <>
                  <section className="custom-tuning-browser" aria-label="Opções da peça">
                    <header className="tuning-browser-heading">
                      <button type="button" className="custom-back" onClick={() => { setCustomCategory(null); setCustomCode(null) }}>
                        <ArrowLeft aria-hidden="true" />Categorias
                      </button>
                      <div><strong>{category.label}</strong><span>/</span><b>{customItem?.label ?? "Sem opções"}</b></div>
                    </header>
                    <div className="tuning-strip">
                      <div className="custom-part-tabs" role="tablist" aria-label="Peças disponíveis">
                        {customItems.map((item, index) => (
                          <button key={item.code} type="button" role="tab" aria-selected={item.code === customItem?.code} data-active={item.code === customItem?.code} onClick={() => setCustomCode(item.code)}>
                            <small>{String(index + 1).padStart(2, "0")}</small><Wrench aria-hidden="true" /><span>{item.label}</span>
                          </button>
                        ))}
                      </div>
                      <div className="custom-options" aria-label="Níveis disponíveis">
                        {customItem?.kind === "rgb" ? (
                          <label className="custom-color-option" data-active={selectedValue !== undefined}>
                            <small>// RGB</small>
                            <input
                              type="color"
                              aria-label={`Selecionar ${customItem.label.toLowerCase()}`}
                              value={colorHex(selectedValue ?? customItem.applied)}
                              disabled={browseOnly || busy}
                              onChange={(event) => void previewOption(customItem, {
                                value: Number.parseInt(event.target.value.slice(1), 16),
                                label: "Cor personalizada",
                                price: customItem.fixedPrice ?? 0,
                              })}
                            />
                            <span>Cor personalizada<em>{selectedValue !== undefined ? "Preview" : customItem.applied !== undefined ? "Aplicado" : "Escolher cor"}</em></span>
                            <strong>{money.format(customItem.fixedPrice ?? 0)}</strong>
                          </label>
                        ) : customItem && customItem.options.length > 24 ? (
                          <label className="custom-select-option" data-active={selectedValue !== undefined}>
                            <small>// CATÁLOGO</small>
                            <select
                              aria-label={`Selecionar ${customItem.label.toLowerCase()}`}
                              value={typeof selectedValue === "number" ? selectedValue : typeof customItem.applied === "number" ? customItem.applied : ""}
                              disabled={browseOnly || busy}
                              onChange={(event) => {
                                const option = customItem.options.find((entry) => entry.value === Number(event.target.value))
                                if (option) void previewOption(customItem, option)
                              }}
                            >
                              <option value="" disabled>Escolha uma opção</option>
                              {customItem.options.map((option) => <option key={String(option.value)} value={Number(option.value)}>{option.label}</option>)}
                            </select>
                            <span>{customItem.label}<em>{selectedValue !== undefined ? "Preview" : "Aplicado"}</em></span>
                            <strong>{money.format(customItem.fixedPrice ?? 0)}</strong>
                          </label>
                        ) : customItem?.options.map((option, index) => {
                          const active = option.value === selectedValue
                          return (
                            <button key={String(option.value)} type="button" data-active={active} disabled={browseOnly || busy} onClick={() => void previewOption(customItem, option)}>
                              <small>// {String(index + 1).padStart(2, "0")}</small>
                              <SlidersHorizontal aria-hidden="true" />
                              <span>{option.label}<em>{option.value === customItem.applied ? "Aplicado" : active && !browseOnly ? "Preview" : "Disponível"}</em></span>
                              <strong>{option.price > 0 ? money.format(option.price) : "Sem custo"}</strong>
                            </button>
                          )
                        })}
                      </div>
                    </div>
                    {notice ? <div className="custom-notice" role="status"><AlertTriangle aria-hidden="true" /><span>{notice}</span></div> : null}
                  </section>
                  <div className="custom-summary">
                  {browseOnly ? (
                    <>
                      <span><PackageCheck aria-hidden="true" />Catálogo somente leitura</span>
                      <strong>SEM PREVIEW</strong>
                      <Button onClick={() => { viewModeRef.current = "atendimento"; setViewMode("atendimento") }}><ArrowLeft data-icon="inline-start" />Abrir atendimento</Button>
                    </>
                  ) : (
                    <>
                      <span><PackageCheck aria-hidden="true" />{Object.keys(customSelections).length} alterações</span>
                      <strong>{money.format(customTotal)}</strong>
                      <Button variant="ghost" disabled={busy} onClick={() => void cancelCustomization()}><Undo2 data-icon="inline-start" />Cancelar</Button>
                      <Button disabled={busy || customTotal <= 0} onClick={() => void submitCustomization()}><ClipboardCheck data-icon="inline-start" />Enviar orçamento</Button>
                    </>
                  )}
                  </div>
                </>
              )}

              <footer className="custom-help">
                <span>Selecionar</span>
                <span><kbd>ESC</kbd> {!category ? customization ? "cancelar preview" : "sair" : "voltar"}</span>
                <button type="button" onClick={() => { controlCamera("general"); setInspectMode(true) }}><Eye aria-hidden="true" />Inspecionar carro</button>
              </footer>
            </>
          ) : (
            <div className="camera-controls" aria-label="Controles da câmera do tuning">
              <span>CÂMERA</span>
              <Button size="sm" variant="secondary" title="Girar para a esquerda" aria-label="Girar câmera para a esquerda" onClick={() => controlCamera("left")}><RotateCcw aria-hidden="true" /></Button>
              <Button size="sm" variant="secondary" title="Girar para a direita" aria-label="Girar câmera para a direita" onClick={() => controlCamera("right")}><RotateCw aria-hidden="true" /></Button>
              <Button size="sm" variant="secondary" title="Aproximar" aria-label="Aproximar câmera" onClick={() => controlCamera("zoomIn")}><ZoomIn aria-hidden="true" /></Button>
              <Button size="sm" variant="secondary" title="Afastar" aria-label="Afastar câmera" onClick={() => controlCamera("zoomOut")}><ZoomOut aria-hidden="true" /></Button>
              <Button size="sm" variant="secondary" onClick={() => controlCamera("general")}><Car data-icon="inline-start" />Geral</Button>
              <Button size="sm" variant="secondary" onClick={() => controlCamera("interior")}><Armchair data-icon="inline-start" />Interior</Button>
              <Button size="sm" onClick={() => { controlCamera("general"); setInspectMode(false) }}><EyeOff data-icon="inline-start" />Mostrar menu</Button>
              <small><kbd>←</kbd><kbd>→</kbd> girar · <kbd>+</kbd><kbd>−</kbd> zoom · <kbd>1</kbd><kbd>2</kbd> visão</small>
            </div>
          )}
        </section>
      </main>
    )
  }

  return (
    <main className="mechanic-stage" data-interface="atendimento">
      <section ref={panelRef} tabIndex={-1} className="mechanic-shell" data-testid="mechanic-panel" data-mode="atendimento" aria-label="Painel de atendimento da oficina">
        <header className="topbar">
          <div className="brand-mark"><Wrench aria-hidden="true" /></div>
          <div className="brand-copy">
            <p className="eyebrow">MZ // MECHANIC {isPreview ? "· PREVIEW" : ""}</p>
            <h1>{context?.workshop.label ?? "Oficina profissional"}</h1>
          </div>
          <div className="escape-hint" aria-label="Pressione Escape para voltar ao jogo"><kbd>ESC</kbd><span>voltar</span></div>
        </header>

        {loading ? <LoadingView /> : contextError ? (
          <ErrorView code={contextError} onRetry={() => void requestRefresh()} onBack={close} />
        ) : context ? (
          <>
            <div className="vehicle-hero">
              <div className="vehicle-symbol"><Car aria-hidden="true" /></div>
              <div className="vehicle-copy">
                <span>{vehicle?.model ?? "Nenhum veículo"}</span>
                <strong>{vehicle?.plate ?? "SEM PLACA"}</strong>
              </div>
              {context.user.isMechanic ? (
                isPreview ? <span className="duty-chip"><i /> Em serviço</span> : (
                  <Button size="sm" variant={context.user.onDuty ? "secondary" : "outline"} disabled={busy} onClick={() => void toggleDuty()}>
                    <Power data-icon="inline-start" />{context.user.onDuty ? "Em serviço" : "Entrar em serviço"}
                  </Button>
                )
              ) : <span className="role-chip">Cliente</span>}
            </div>

            <ol className="workflow" aria-label="Etapas da ordem de serviço">
              {["Atendimento", "Diagnóstico", "Orçamento", "Execução"].map((label, index) => (
                <li key={label} data-state={index < stage ? "done" : index === stage ? "current" : "next"}>
                  <span>{index < stage ? <BadgeCheck aria-hidden="true" /> : index + 1}</span>
                  <small>{label}</small>
                </li>
              ))}
            </ol>

            {notice ? <div className="notice" role="status"><AlertTriangle aria-hidden="true" /><span>{notice}</span></div> : null}
            {!notice && context.user.mechanicError === "missing_permission" ? <div className="notice" role="status"><ShieldCheck aria-hidden="true" /><span>{errorLabels.missing_permission}</span></div> : null}

            <ScrollArea className="panel-scroll">
              <div className="panel-content">
                {selected ? (
                  <Card className="work-card" data-state={selected.state}>
                    <CardHeader>
                      <div className="order-heading">
                        <div><p className="eyebrow">ORDEM {selected.id.slice(-8).toUpperCase()}</p><CardTitle>{status(selected)}</CardTitle></div>
                        <span className="bay-chip">{selected.bayCode.replace("_", " ")}</span>
                      </div>
                      <CardDescription>{selected.state === "failed"
                        ? errorLabels[selected.failureCode ?? ""] ?? "A execução foi encerrada sem alteração persistida."
                        : `${selected.vehicle.plate} · validação e preço no servidor`}</CardDescription>
                    </CardHeader>
                    <CardContent className="work-details">
                      {selected.diagnostic ? (
                        <div className="condition-grid">
                          <div><Gauge aria-hidden="true" /><span>Motor</span><strong>{condition(selected.diagnostic.engine)}</strong></div>
                          <div><Car aria-hidden="true" /><span>Carroceria</span><strong>{condition(selected.diagnostic.body)}</strong></div>
                        </div>
                      ) : (
                        <div className="pending-reading"><Activity aria-hidden="true" /><span>A leitura do veículo será registrada ao diagnosticar.</span></div>
                      )}

                      {selected.quote?.services?.length ? (
                        <div className="quote-block">
                          <p className="section-label">ORÇAMENTO</p>
                          {selected.quote.services.map((service) => (
                            <div className="quote-line" key={service.code}><span>{service.label}</span><strong>{money.format(service.price)}</strong></div>
                          ))}
                          <div className="quote-total"><span>Total autorizado</span><strong>{money.format(selected.quote.total ?? 0)}</strong></div>
                        </div>
                      ) : null}

                      {selected.state === "pending_reconciliation" ? (
                        <div className="protected-state"><ShieldCheck aria-hidden="true" /><div><strong>Ordem protegida</strong><span>A cobrança requer revisão; nenhuma nova execução será iniciada.</span></div></div>
                      ) : null}
                      {selected.state === "completed" ? (
                        <div className="success-state"><BadgeCheck aria-hidden="true" /><div><strong>Serviço finalizado</strong><span>Aplicação e persistência foram confirmadas.</span></div></div>
                      ) : null}
                    </CardContent>
                    <CardFooter className="action-row">
                      {context.vehicle && ["completed", "cancelled", "failed"].includes(selected.state) ? (
                        <Button disabled={busy} onClick={() => void createOrder()}><ClipboardList data-icon="inline-start" />Abrir nova OS</Button>
                      ) : null}
                      {context.user.isMechanic && !selected.assignedMechanicCitizenId && !["completed", "cancelled", "failed"].includes(selected.state) ? (
                        <Button disabled={busy || !context.user.onDuty} onClick={() => void act("acceptOrder", selected)}>Assumir OS<ChevronRight data-icon="inline-end" /></Button>
                      ) : null}
                      {context.user.isMechanic && isAssigned && selected.state === "created" ? (
                        <Button disabled={busy} onClick={() => void act("diagnoseOrder", selected)}><Activity data-icon="inline-start" />Diagnosticar</Button>
                      ) : null}
                      {context.user.isMechanic && isAssigned && selected.state === "created" && context.capabilities.customization ? (
                        <Button variant="outline" disabled={busy} onClick={() => void beginCustomization()}><SlidersHorizontal data-icon="inline-start" />Customizar</Button>
                      ) : null}
                      {isCustomer && selected.state === "quoted" ? (
                        <Button disabled={busy} onClick={() => void act("acceptQuote", selected)}><ClipboardCheck data-icon="inline-start" />Aprovar orçamento</Button>
                      ) : null}
                      {context.user.isMechanic && isAssigned && selected.state === "accepted" ? (
                        <Button disabled={busy} onClick={() => void act("executeOrder", selected)}><Wrench data-icon="inline-start" />Cobrar e executar</Button>
                      ) : null}
                      {canCancel ? <Button variant="ghost" disabled={busy} onClick={() => setPendingCancel(selected)}>Cancelar OS</Button> : null}
                    </CardFooter>
                  </Card>
                ) : vehicle ? (
                  <Card className="work-card intake-card">
                    <CardHeader><p className="eyebrow">ATENDIMENTO DIRETO</p><CardTitle>Veículo pronto para atendimento</CardTitle><CardDescription>Use o target para reparo ou o marcador da vaga para tuning. O orçamento segue direto ao proprietário.</CardDescription></CardHeader>
                    <CardContent className="condition-grid">
                      <div><Gauge aria-hidden="true" /><span>Motor</span><strong>{condition(vehicle.engine)}</strong></div>
                      <div><Car aria-hidden="true" /><span>Carroceria</span><strong>{condition(vehicle.body)}</strong></div>
                    </CardContent>
                  </Card>
                ) : (
                  <div className="empty-state"><Car aria-hidden="true" /><h2>Nenhum veículo selecionado</h2><p>Aproxime-se de um veículo e reabra pelo radial, ou use a interação diretamente nele. Duty e fila continuam disponíveis.</p></div>
                )}

                {pendingCancel ? (
                  <div className="confirm-card" role="alertdialog" aria-labelledby="cancel-title" aria-describedby="cancel-description">
                    <p className="eyebrow">CONFIRMAÇÃO</p>
                    <h2 id="cancel-title">Cancelar esta ordem?</h2>
                    <p id="cancel-description">O veículo será liberado. Uma ordem já cobrada não pode ser cancelada por este fluxo.</p>
                    <div><Button variant="outline" onClick={() => setPendingCancel(null)}>Voltar</Button><Button variant="destructive" disabled={busy} onClick={() => { void act("cancelOrder", pendingCancel, "cancelado pelo operador"); setPendingCancel(null) }}>Confirmar cancelamento</Button></div>
                  </div>
                ) : null}

                {context.user.isMechanic && context.queue.filter((order) => order.id !== selected?.id).length ? (
                  <section className="queue-list" aria-labelledby="queue-title">
                    <div className="section-heading"><div><p className="eyebrow">FILA DA OFICINA</p><h2 id="queue-title">Próximos atendimentos</h2></div><span>{context.queue.length}</span></div>
                    {context.queue.filter((order) => order.id !== selected?.id).map((order) => (
                      <div className="queue-row" key={order.id}><div><strong>{order.vehicle.plate}</strong><span>{status(order)}</span></div><Button size="sm" variant="outline" disabled={busy || !context.user.onDuty} onClick={() => void act("acceptOrder", order)}>Assumir</Button></div>
                    ))}
                  </section>
                ) : null}
              </div>
            </ScrollArea>

            <footer className="panel-footer"><ShieldCheck aria-hidden="true" /><span>Permissão, preço e cobrança validados no servidor</span></footer>
          </>
        ) : null}
      </section>
    </main>
  )
}
