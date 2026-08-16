/**
 * Supabase Database Types
 *
 * Veritabanı tabloları oluşturulduktan sonra
 * `supabase gen types typescript` komutu ile otomatik üretilecek.
 */

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
      // Tablolar oluşturulduktan sonra eklenecek
    }
    Views: {
      // View'lar oluşturulduktan sonra eklenecek
    }
    Functions: {
      // Fonksiyonlar oluşturulduktan sonra eklenecek
    }
    Enums: {
      // Enum'lar oluşturulduktan sonra eklenecek
    }
  }
}
