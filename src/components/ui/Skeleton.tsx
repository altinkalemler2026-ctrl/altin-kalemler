import { HTMLAttributes, forwardRef } from "react"

import { cn } from "@/lib/ui/cn"

export interface SkeletonProps extends HTMLAttributes<HTMLDivElement> {
  /** İçerik yüksekliğini taklit etmek için satır sayısı. */
  lines?: number
}

export const Skeleton = forwardRef<HTMLDivElement, SkeletonProps>(
  function Skeleton({ lines = 1, className, ...props }, ref) {
    return (
      <div
        ref={ref}
        aria-hidden="true"
        className={cn("space-y-2", className)}
        {...props}
      >
        {Array.from({ length: lines }, (_, index) => (
          <div
            key={index}
            className="h-4 w-full animate-pulse rounded-md bg-surface-muted"
          />
        ))}
      </div>
    )
  }
)
