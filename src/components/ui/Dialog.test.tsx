/**
 * Dialog testleri — aç/kapa, Esc, arka plan, aria-modal, odak.
 */

import { useState } from "react"
import { render, screen, fireEvent } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { Dialog } from "./Dialog"

function DialogHarness({ onClose }: { onClose: () => void }) {
  const [open, setOpen] = useState(true)

  return (
    <Dialog
      open={open}
      onClose={() => {
        setOpen(false)
        onClose()
      }}
      title="Örnek Başlık"
    >
      İçerik metni
    </Dialog>
  )
}

describe("Dialog", () => {
  it("open=true iken role=dialog ve aria-modal ile render edilir", () => {
    render(<Dialog open onClose={vi.fn()} title="Başlık">İçerik</Dialog>)

    const dialog = screen.getByRole("dialog")

    expect(dialog).toHaveAttribute("aria-modal", "true")
    expect(dialog).toHaveAttribute("aria-label", "Başlık")
    expect(screen.getByText("İçerik")).toBeInTheDocument()
  })

  it("open=false iken render edilmez", () => {
    render(<Dialog open={false} onClose={vi.fn()} title="Başlık" />)

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
  })

  it("Esc ile kapanır", () => {
    const onClose = vi.fn()

    render(<DialogHarness onClose={onClose} />)

    fireEvent.keyDown(document, { key: "Escape" })

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it("arka plan butonu ile kapanır", () => {
    const onClose = vi.fn()

    render(<DialogHarness onClose={onClose} />)

    fireEvent.click(screen.getByRole("button", { name: "Diyalogu kapat" }))

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it("açılışta kapatma düğmesine odaklanır", () => {
    render(<Dialog open onClose={vi.fn()} title="Başlık" />)

    expect(screen.getByRole("button", { name: "Kapat" })).toHaveFocus()
  })
})
