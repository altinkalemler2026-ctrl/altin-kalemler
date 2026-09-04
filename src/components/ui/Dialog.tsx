"use client"

import {
  DialogHTMLAttributes,
  ReactNode,
  forwardRef,
  useEffect,
  useRef,
} from "react"

import { cn } from "@/lib/ui/cn"

export interface DialogProps extends DialogHTMLAttributes<HTMLDivElement> {
  open: boolean
  onClose: () => void
  title: string
  children?: ReactNode
}

/**
 * Erişilebilir temel Dialog: Esc ve arka plan tıklaması ile kapanır,
 * açılışta kapatma düğmesine odaklanır.
 */
export const Dialog = forwardRef<HTMLDivElement, DialogProps>(function Dialog(
  { open, onClose, title, children, className, ...props },
  ref
) {
  const closeButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (!open) return

    closeButtonRef.current?.focus()

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose()
      }
    }

    document.addEventListener("keydown", handleKeyDown)

    return () => {
      document.removeEventListener("keydown", handleKeyDown)
    }
  }, [open, onClose])

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <button
        type="button"
        aria-label="Diyalogu kapat"
        onClick={onClose}
        className="absolute inset-0 h-full w-full cursor-default bg-navy-900/60"
      />

      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={cn(
          "relative z-10 w-full max-w-md rounded-2xl border border-border bg-surface p-6 shadow-modal",
          className
        )}
        {...props}
      >
        <div className="flex items-start justify-between gap-4">
          <h2 className="text-lg font-bold text-ink">{title}</h2>

          <button
            ref={closeButtonRef}
            type="button"
            onClick={onClose}
            aria-label="Kapat"
            className="flex h-11 w-11 items-center justify-center rounded-xl text-ink-muted transition hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>

        <div className="mt-4 text-sm text-ink">{children}</div>
      </div>
    </div>
  )
})
