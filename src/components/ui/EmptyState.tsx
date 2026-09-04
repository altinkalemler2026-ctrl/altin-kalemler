import { HTMLAttributes, forwardRef } from "react"

import { cn } from "@/lib/ui/cn"

export interface EmptyStateProps extends HTMLAttributes<HTMLDivElement> {
  icon?: React.ReactNode
  title: string
  description?: string
  action?: React.ReactNode
}

export const EmptyState = forwardRef<HTMLDivElement, EmptyStateProps>(
  function EmptyState(
    { icon, title, description, action, className, ...props },
    ref
  ) {
    return (
      <div
        ref={ref}
        className={cn(
          "flex flex-col items-center justify-center rounded-2xl border border-dashed border-border-strong bg-surface px-6 py-10 text-center",
          className
        )}
        {...props}
      >
        {icon && <div className="mb-3 text-3xl">{icon}</div>}

        <p className="text-base font-semibold text-ink">{title}</p>

        {description && (
          <p className="mt-1 max-w-sm text-sm text-ink-muted">{description}</p>
        )}

        {action && <div className="mt-4">{action}</div>}
      </div>
    )
  }
)
