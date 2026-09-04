import { HTMLAttributes, forwardRef } from "react"

import { cn } from "@/lib/ui/cn"

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  padding?: "none" | "sm" | "md" | "lg"
}

const PADDING_CLASSES = {
  none: "",
  sm: "p-4",
  md: "p-6",
  lg: "p-6 sm:p-8",
} as const

export const Card = forwardRef<HTMLDivElement, CardProps>(function Card(
  { padding = "md", className, ...props },
  ref
) {
  return (
    <div
      ref={ref}
      className={cn(
        "rounded-2xl border border-border bg-surface shadow-card",
        PADDING_CLASSES[padding],
        className
      )}
      {...props}
    />
  )
})
