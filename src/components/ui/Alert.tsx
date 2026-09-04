import { HTMLAttributes, forwardRef } from "react"

import { cn } from "@/lib/ui/cn"

export type AlertVariant = "info" | "success" | "warning" | "danger"

const VARIANT_CLASSES: Record<AlertVariant, string> = {
  info: "border-navy-100 bg-navy-100 text-navy-900",
  success: "border-success-700 bg-success-100 text-success-700",
  warning: "border-warning-900 bg-warning-100 text-warning-900",
  danger: "border-danger-700 bg-danger-100 text-danger-700",
}

const VARIANT_TITLES: Record<AlertVariant, string> = {
  info: "Bilgi",
  success: "Başarılı",
  warning: "Dikkat",
  danger: "Hata",
}

export interface AlertProps extends HTMLAttributes<HTMLDivElement> {
  variant?: AlertVariant
  title?: string
}

export const Alert = forwardRef<HTMLDivElement, AlertProps>(function Alert(
  { variant = "info", title, className, children, ...props },
  ref
) {
  return (
    <div
      ref={ref}
      role="alert"
      aria-live="polite"
      className={cn(
        "rounded-xl border px-4 py-3 text-sm",
        VARIANT_CLASSES[variant],
        className
      )}
      {...props}
    >
      <p className="font-semibold">
        {title ?? VARIANT_TITLES[variant]}
      </p>

      {children && <div className="mt-1">{children}</div>}
    </div>
  )
})
