export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      student_profiles: {
        Row: {
          id: string
          grade_level: number
          nickname: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          grade_level: number
          nickname: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          grade_level?: number
          nickname?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: Record<string, never>
  }
}