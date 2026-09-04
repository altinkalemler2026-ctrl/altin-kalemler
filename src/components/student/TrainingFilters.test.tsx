/**
 * TrainingFilters testleri — konu/kazanım filtreleri.
 *
 * - Seçenekler yalnız gerçek RPC listesinden (props) gelir
 * - Konu seçimi URL'e ?topic= taşır ve kazanım filtresini temizler
 * - Kazanım seçimi URL'e ?outcome= taşır ve konu filtresini temizler
 * - "Tümü" seçimi filtreleri kaldırır
 * - Sınıf seçici yoktur
 */

import { render, screen, fireEvent } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const pushMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock }),
}))

import TrainingFilters from "./TrainingFilters"

const TOPICS = [
  { topicId: "11111111-1111-4111-8111-000000000001", topicName: "Kesirler" },
  { topicId: "11111111-1111-4111-8111-000000000002", topicName: "Üslü Sayılar" },
]

const OUTCOMES = [
  {
    outcomeId: "22222222-2222-4222-8222-000000000001",
    outcomeText: "Ondalık gösterimde kesirleri çözer.",
  },
]

const SUBJECT_ID = "33333333-3333-4333-8333-000000000001"

beforeEach(() => {
  pushMock.mockReset()
})

describe("TrainingFilters", () => {
  it("konu ve kazanım seçeneklerini gerçek listeden render eder", () => {
    render(
      <TrainingFilters
        subjectId={SUBJECT_ID}
        topics={TOPICS}
        outcomes={OUTCOMES}
        activeTopicId={null}
        activeOutcomeId={null}
      />
    )

    expect(screen.getByLabelText("Konu filtresi")).toBeInTheDocument()
    expect(
      screen.getByRole("option", { name: "Kesirler" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("option", { name: "Üslü Sayılar" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("option", { name: "Ondalık gösterimde kesirleri çözer." })
    ).toBeInTheDocument()
  })

  it("konu seçimi ?topic= ile navigasyon yapar ve kazanımı temizler", () => {
    render(
      <TrainingFilters
        subjectId={SUBJECT_ID}
        topics={TOPICS}
        outcomes={OUTCOMES}
        activeTopicId={null}
        activeOutcomeId={OUTCOMES[0].outcomeId}
      />
    )

    fireEvent.change(screen.getByLabelText("Konu filtresi"), {
      target: { value: TOPICS[0].topicId },
    })

    expect(pushMock).toHaveBeenCalledWith(
      `/training/${SUBJECT_ID}?topic=${TOPICS[0].topicId}`
    )
  })

  it("kazanım seçimi ?outcome= ile navigasyon yapar ve konuyu temizler", () => {
    render(
      <TrainingFilters
        subjectId={SUBJECT_ID}
        topics={TOPICS}
        outcomes={OUTCOMES}
        activeTopicId={TOPICS[0].topicId}
        activeOutcomeId={null}
      />
    )

    fireEvent.change(screen.getByLabelText("Kazanım filtresi"), {
      target: { value: OUTCOMES[0].outcomeId },
    })

    expect(pushMock).toHaveBeenCalledWith(
      `/training/${SUBJECT_ID}?outcome=${OUTCOMES[0].outcomeId}`
    )
  })

  it("Tümü seçimi filtresiz navigasyon yapar", () => {
    render(
      <TrainingFilters
        subjectId={SUBJECT_ID}
        topics={TOPICS}
        outcomes={OUTCOMES}
        activeTopicId={TOPICS[0].topicId}
        activeOutcomeId={null}
      />
    )

    fireEvent.change(screen.getByLabelText("Konu filtresi"), {
      target: { value: "" },
    })

    expect(pushMock).toHaveBeenCalledWith(`/training/${SUBJECT_ID}`)
  })

  it("sınıf seçici yoktur", () => {
    render(
      <TrainingFilters
        subjectId={SUBJECT_ID}
        topics={TOPICS}
        outcomes={OUTCOMES}
        activeTopicId={null}
        activeOutcomeId={null}
      />
    )

    expect(screen.queryByLabelText(/Sınıf/)).not.toBeInTheDocument()
  })
})
