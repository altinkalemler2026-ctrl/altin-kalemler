import { HTMLAttributes, forwardRef } from "react"

import { cn } from "@/lib/ui/cn"

export type BadgeVariant = "neutral" | "navy" | "gold" | "teal" | "success" | "danger"

const VARIANT_CLASSES: Record<BadgeVariant, string> = {
  neutral: "border-border bg-surface-muted text-ink-muted",
  navy: "border-navy-100 bg-navy-100 text-navy-900",
  gold: "border-gold-500 bg-gold-100 text-navy-900",
  teal: "border-teal-700 bg-teal-100 text-teal-700",
  success: "border-success-700 bg-success-100 text-success-700",
  danger: "border-danger-700 bg-danger-100 text-danger-700",
}

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant
}

export const Badge = forwardRef<HTMLSpanElement, BadgeProps>(function Badge(
  { variant = "neutral", className, ...props },
  ref
) {
  return (
    <span
      ref={ref}
      className={cn(
        "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold",
        VARIANT_CLASSES[variant],
        className
      )}
      {...props}
    />
  )
})
