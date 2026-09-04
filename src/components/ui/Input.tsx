import { InputHTMLAttributes, forwardRef, useId } from "react"

import { cn } from "@/lib/ui/cn"

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string
  error?: string
  hint?: string
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { label, error, hint, className, id, ...props },
  ref
) {
  const autoId = useId()
  const inputId = id ?? autoId
  const describedBy = error
    ? `${inputId}-error`
    : hint
      ? `${inputId}-hint`
      : undefined

  return (
    <div className="w-full">
      <label
        htmlFor={inputId}
        className="mb-1.5 block text-sm font-medium text-ink"
      >
        {label}
      </label>

      <input
        ref={ref}
        id={inputId}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy}
        className={cn(
          "min-h-11 w-full rounded-xl border bg-surface px-4 py-2.5 text-ink outline-none transition placeholder:text-ink-muted focus:ring-2 focus:ring-teal-600 focus:ring-offset-1",
          error ? "border-danger-700" : "border-border",
          className
        )}
        {...props}
      />

      {hint && !error && (
        <p id={`${inputId}-hint`} className="mt-1 text-sm text-ink-muted">
          {hint}
        </p>
      )}

      {error && (
        <p
          id={`${inputId}-error`}
          role="alert"
          className="mt-1 text-sm font-medium text-danger-700"
        >
          {error}
        </p>
      )}
    </div>
  )
})
