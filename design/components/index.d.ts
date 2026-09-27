/** Dockd e um sistema de classes CSS; estes tipos documentam o que cada function component Phoenix recebe. */
export type Status = "quero" | "backlog" | "jogando" | "zerado" | "larguei";
export type Media = "fisico" | "digital" | "key-card";
export interface Poster { title: string; coverUrl?: string; status?: Status; href?: string; size?: "grid" | "sm"; caption?: { platforms: string; exclusive: boolean } }
export interface StatusChip { status: Status; size?: "md" | "sm" }
export interface MediaTag { media: Media }
export interface Button { variant: "primary" | "secondary"; size?: "md" | "sm"; disabled?: boolean; label: string }
export interface Tabs { tabs: { label: string; count: number; selected?: boolean; href: string }[] }
export interface NavBar { current: "Biblioteca" | "Comprar" | "Descobrir"; search?: string }
export interface SearchField { placeholder: string; value?: string }
export interface GameCard { title: string; coverUrl?: string; meta: string; status?: Status; href: string }
export interface GameRow { title: string; lead: { coverUrl?: string } | { date: DateBlock }; meta: string; end: Price | StatusChip | Button }
export interface DateBlock { date: string; precision: "day" | "month" | "year"; soon?: boolean }
export interface Price { cents?: number; observedAt?: string }
export interface EmptyState { text: string; action?: { label: string; href: string } }
/** The one status control, on covers (size sm) and on the game page (md). `null` clears the status and takes the game out of the library. */
export interface StatusMenu { value: Status | null; options: Status[]; since?: string; size?: "md" | "sm"; ask?: { label: string }[]; onChange: (next: Status | null) => void }
export interface History { items: { what: string; relative: string; who: string; current?: boolean }[] }
export interface SectionHead { title: string; count?: number; action?: { label: string; href: string } }
/** The one line at the end of every screen but Entrar: wordmark, Sobre and the IGDB credit. `aboveBottomNav` clears the phone bottom navigation. */
export interface Footer { aboveBottomNav?: boolean }
