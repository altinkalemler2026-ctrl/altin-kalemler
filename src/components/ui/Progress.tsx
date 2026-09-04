import { HTMLAttributes, forwardRef } from "react"

import { cn } from "@/lib/ui/cn"

export interface ProgressProps extends HTMLAttributes<HTMLDivElement> {
  value: number
  max?: number
  label: string
}

export const Progress = forwardRef<HTMLDivElement, ProgressProps>(
  function Progress({ value, max = 100, label, className, ...props }, ref) {
    const safeMax = max > 0 ? max : 1
    const clamped = Math.min(Math.max(value, 0), safeMax)
    const percent = Math.round((clamped / safeMax) * 100)

    return (
      <div
        ref={ref}
        role="progressbar"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={safeMax}
        aria-valuenow={clamped}
        className={cn("w-full", className)}
        {...props}
      >
        <div className="h-2.5 w-full overflow-hidden rounded-full bg-surface-muted">
          <div
            className="h-full rounded-full bg-teal-600 transition-all"
            style={{ width: `${percent}%` }}
          />
        </div>

        <span className="mt-1 block text-xs font-medium text-ink-muted">
          {label}: {percent}%
        </span>
      </div>
    )
  }
)
