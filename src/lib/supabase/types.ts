export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      academic_weeks: {
        Row: {
          academic_year: string
          ends_at: string
          starts_at: string
          week: number
        }
        Insert: {
          academic_year: string
          ends_at: string
          starts_at: string
          week: number
        }
        Update: {
          academic_year?: string
          ends_at?: string
          starts_at?: string
          week?: number
        }
        Relationships: []
      }
      admin_audit_log: {
        Row: {
          action_code: string
          actor_user_id: string | null
          after_data: Json | null
          before_data: Json | null
          entity_id: string | null
          entity_type: string
          id: string
          performed_at: string
        }
        Insert: {
          action_code: string
          actor_user_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          entity_id?: string | null
          entity_type: string
          id?: string
          performed_at?: string
        }
        Update: {
          action_code?: string
          actor_user_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          entity_id?: string | null
          entity_type?: string
          id?: string
          performed_at?: string
        }
        Relationships: []
      }
      admin_permissions: {
        Row: {
          created_at: string
          description: string | null
          id: string
          name: string
          permission_code: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          name: string
          permission_code: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          permission_code?: string
        }
        Relationships: []
      }
      admin_role_permissions: {
        Row: {
          created_at: string
          permission_id: string
          role_id: string
        }
        Insert: {
          created_at?: string
          permission_id: string
          role_id: string
        }
        Update: {
          created_at?: string
          permission_id?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_role_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "admin_permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "admin_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_roles: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          role_code: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          role_code: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          role_code?: string
          updated_at?: string
        }
        Relationships: []
      }
      admin_user_roles: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          role_id: string
          user_id: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          role_id: string
          user_id: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          role_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "admin_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_executions: {
        Row: {
          agent_id: string | null
          agent_version_id: string | null
          ai_job_id: string
          completed_at: string | null
          confidence_score: number | null
          cost_amount: number | null
          error_message: string | null
          execution_role: string
          id: string
          input_snapshot: Json
          input_tokens: number | null
          model_name: string | null
          output_snapshot: Json | null
          output_tokens: number | null
          prompt_version: string | null
          provider_name: string | null
          started_at: string
          status: string
        }
        Insert: {
          agent_id?: string | null
          agent_version_id?: string | null
          ai_job_id: string
          completed_at?: string | null
          confidence_score?: number | null
          cost_amount?: number | null
          error_message?: string | null
          execution_role: string
          id?: string
          input_snapshot?: Json
          input_tokens?: number | null
          model_name?: string | null
          output_snapshot?: Json | null
          output_tokens?: number | null
          prompt_version?: string | null
          provider_name?: string | null
          started_at?: string
          status?: string
        }
        Update: {
          agent_id?: string | null
          agent_version_id?: string | null
          ai_job_id?: string
          completed_at?: string | null
          confidence_score?: number | null
          cost_amount?: number | null
          error_message?: string | null
          execution_role?: string
          id?: string
          input_snapshot?: Json
          input_tokens?: number | null
          model_name?: string | null
          output_snapshot?: Json | null
          output_tokens?: number | null
          prompt_version?: string | null
          provider_name?: string | null
          started_at?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_executions_agent_id_fkey"
            columns: ["agent_id"]
            isOneToOne: false
            referencedRelation: "ai_agents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_executions_agent_version_id_fkey"
            columns: ["agent_version_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_executions_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_versions: {
        Row: {
          agent_id: string
          configuration: Json
          created_at: string
          id: string
          is_active: boolean
          model_name: string | null
          prompt_template: string | null
          provider_name: string | null
          system_instructions: string | null
          version: string
        }
        Insert: {
          agent_id: string
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          model_name?: string | null
          prompt_template?: string | null
          provider_name?: string | null
          system_instructions?: string | null
          version: string
        }
        Update: {
          agent_id?: string
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          model_name?: string | null
          prompt_template?: string | null
          provider_name?: string | null
          system_instructions?: string | null
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_versions_agent_id_fkey"
            columns: ["agent_id"]
            isOneToOne: false
            referencedRelation: "ai_agents"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agents: {
        Row: {
          agent_category: string
          agent_code: string
          can_generate_content: boolean
          can_promote_to_question_bank: boolean
          can_recommend_approval: boolean
          can_validate_content: boolean
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          risk_level: string
          updated_at: string
        }
        Insert: {
          agent_category: string
          agent_code: string
          can_generate_content?: boolean
          can_promote_to_question_bank?: boolean
          can_recommend_approval?: boolean
          can_validate_content?: boolean
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          risk_level?: string
          updated_at?: string
        }
        Update: {
          agent_category?: string
          agent_code?: string
          can_generate_content?: boolean
          can_promote_to_question_bank?: boolean
          can_recommend_approval?: boolean
          can_validate_content?: boolean
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          risk_level?: string
          updated_at?: string
        }
        Relationships: []
      }
      ai_answer_verification_runs: {
        Row: {
          ai_job_id: string | null
          consensus_answer: string | null
          consensus_status: string
          created_at: string
          human_decision: string | null
          human_final_answer: string | null
          human_review_required: boolean
          human_reviewed_at: string | null
          human_reviewed_by: string | null
          id: string
          metadata: Json
          minimum_confidence: number
          proposed_answer: string
          solver_1_answer: string | null
          solver_1_completed_at: string | null
          solver_1_confidence: number | null
          solver_1_model: string | null
          solver_1_prompt_version: string | null
          solver_1_provider: string | null
          solver_1_reasoning_summary: string | null
          solver_1_result: Json
          solver_2_answer: string | null
          solver_2_completed_at: string | null
          solver_2_confidence: number | null
          solver_2_model: string | null
          solver_2_prompt_version: string | null
          solver_2_provider: string | null
          solver_2_reasoning_summary: string | null
          solver_2_result: Json
          staging_question_id: string
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          consensus_answer?: string | null
          consensus_status?: string
          created_at?: string
          human_decision?: string | null
          human_final_answer?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          minimum_confidence?: number
          proposed_answer: string
          solver_1_answer?: string | null
          solver_1_completed_at?: string | null
          solver_1_confidence?: number | null
          solver_1_model?: string | null
          solver_1_prompt_version?: string | null
          solver_1_provider?: string | null
          solver_1_reasoning_summary?: string | null
          solver_1_result?: Json
          solver_2_answer?: string | null
          solver_2_completed_at?: string | null
          solver_2_confidence?: number | null
          solver_2_model?: string | null
          solver_2_prompt_version?: string | null
          solver_2_provider?: string | null
          solver_2_reasoning_summary?: string | null
          solver_2_result?: Json
          staging_question_id: string
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          consensus_answer?: string | null
          consensus_status?: string
          created_at?: string
          human_decision?: string | null
          human_final_answer?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          minimum_confidence?: number
          proposed_answer?: string
          solver_1_answer?: string | null
          solver_1_completed_at?: string | null
          solver_1_confidence?: number | null
          solver_1_model?: string | null
          solver_1_prompt_version?: string | null
          solver_1_provider?: string | null
          solver_1_reasoning_summary?: string | null
          solver_1_result?: Json
          solver_2_answer?: string | null
          solver_2_completed_at?: string | null
          solver_2_confidence?: number | null
          solver_2_model?: string | null
          solver_2_prompt_version?: string | null
          solver_2_provider?: string | null
          solver_2_reasoning_summary?: string | null
          solver_2_result?: Json
          staging_question_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_answer_verification_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_answer_verification_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_curriculum_fit_reviews: {
        Row: {
          confidence_score: number
          created_at: string
          details: Json
          grade_drift_detected: boolean
          grade_fit_score: number | null
          id: string
          model_name: string | null
          outcome_drift_detected: boolean
          outcome_fit_score: number | null
          prerequisite_details: Json
          prerequisite_violation: boolean
          prompt_version: string | null
          provider_name: string | null
          required_prior_knowledge: Json
          review_summary: string | null
          reviewer_number: number
          subject_fit_score: number | null
          subtopic_drift_detected: boolean
          subtopic_fit_score: number | null
          suggested_grade_level: number | null
          suggested_outcome_id: string | null
          suggested_subject_id: string | null
          suggested_subtopic_id: string | null
          suggested_topic_id: string | null
          topic_drift_detected: boolean
          topic_fit_score: number | null
          verification_run_id: string
        }
        Insert: {
          confidence_score: number
          created_at?: string
          details?: Json
          grade_drift_detected?: boolean
          grade_fit_score?: number | null
          id?: string
          model_name?: string | null
          outcome_drift_detected?: boolean
          outcome_fit_score?: number | null
          prerequisite_details?: Json
          prerequisite_violation?: boolean
          prompt_version?: string | null
          provider_name?: string | null
          required_prior_knowledge?: Json
          review_summary?: string | null
          reviewer_number: number
          subject_fit_score?: number | null
          subtopic_drift_detected?: boolean
          subtopic_fit_score?: number | null
          suggested_grade_level?: number | null
          suggested_outcome_id?: string | null
          suggested_subject_id?: string | null
          suggested_subtopic_id?: string | null
          suggested_topic_id?: string | null
          topic_drift_detected?: boolean
          topic_fit_score?: number | null
          verification_run_id: string
        }
        Update: {
          confidence_score?: number
          created_at?: string
          details?: Json
          grade_drift_detected?: boolean
          grade_fit_score?: number | null
          id?: string
          model_name?: string | null
          outcome_drift_detected?: boolean
          outcome_fit_score?: number | null
          prerequisite_details?: Json
          prerequisite_violation?: boolean
          prompt_version?: string | null
          provider_name?: string | null
          required_prior_knowledge?: Json
          review_summary?: string | null
          reviewer_number?: number
          subject_fit_score?: number | null
          subtopic_drift_detected?: boolean
          subtopic_fit_score?: number | null
          suggested_grade_level?: number | null
          suggested_outcome_id?: string | null
          suggested_subject_id?: string | null
          suggested_subtopic_id?: string | null
          suggested_topic_id?: string | null
          topic_drift_detected?: boolean
          topic_fit_score?: number | null
          verification_run_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_curriculum_fit_reviews_suggested_outcome_id_fkey"
            columns: ["suggested_outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_reviews_suggested_subject_id_fkey"
            columns: ["suggested_subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_reviews_suggested_subtopic_id_fkey"
            columns: ["suggested_subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_reviews_suggested_topic_id_fkey"
            columns: ["suggested_topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_reviews_verification_run_id_fkey"
            columns: ["verification_run_id"]
            isOneToOne: false
            referencedRelation: "ai_curriculum_fit_overview"
            referencedColumns: ["verification_run_id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_reviews_verification_run_id_fkey"
            columns: ["verification_run_id"]
            isOneToOne: false
            referencedRelation: "ai_curriculum_fit_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_curriculum_fit_runs: {
        Row: {
          ai_job_id: string | null
          created_at: string
          expected_curriculum_version_id: string | null
          expected_grade_level: number
          expected_outcome_id: string | null
          expected_subject_id: string
          expected_subtopic_id: string | null
          expected_topic_id: string | null
          human_decision: string | null
          human_review_required: boolean
          human_reviewed_at: string | null
          human_reviewed_by: string | null
          id: string
          metadata: Json
          minimum_confidence: number
          staging_question_id: string
          status: string
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          created_at?: string
          expected_curriculum_version_id?: string | null
          expected_grade_level: number
          expected_outcome_id?: string | null
          expected_subject_id: string
          expected_subtopic_id?: string | null
          expected_topic_id?: string | null
          human_decision?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          minimum_confidence?: number
          staging_question_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          created_at?: string
          expected_curriculum_version_id?: string | null
          expected_grade_level?: number
          expected_outcome_id?: string | null
          expected_subject_id?: string
          expected_subtopic_id?: string | null
          expected_topic_id?: string | null
          human_decision?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          minimum_confidence?: number
          staging_question_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_curriculum_fit_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_curriculum_version_id_fkey"
            columns: ["expected_curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_outcome_id_fkey"
            columns: ["expected_outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_subject_id_fkey"
            columns: ["expected_subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_subtopic_id_fkey"
            columns: ["expected_subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_topic_id_fkey"
            columns: ["expected_topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_generation_specs: {
        Row: {
          cognitive_type: string | null
          competition_factory_dispatch_id: string | null
          competition_generation_request_id: string | null
          constraints: Json
          created_at: string
          created_by: string | null
          curriculum_version_id: string | null
          desired_count: number
          difficulty: string | null
          generation_instructions: string | null
          grade_level: number
          id: string
          is_new_generation: boolean | null
          max_solve_time_seconds: number | null
          min_solve_time_seconds: number | null
          originality_min_score: number | null
          outcome_id: string | null
          primary_question_type: string | null
          secondary_question_type: string | null
          similarity_max_score: number | null
          status: string
          subject_id: string
          subtopic_id: string | null
          topic_id: string | null
          updated_at: string
        }
        Insert: {
          cognitive_type?: string | null
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          constraints?: Json
          created_at?: string
          created_by?: string | null
          curriculum_version_id?: string | null
          desired_count: number
          difficulty?: string | null
          generation_instructions?: string | null
          grade_level: number
          id?: string
          is_new_generation?: boolean | null
          max_solve_time_seconds?: number | null
          min_solve_time_seconds?: number | null
          originality_min_score?: number | null
          outcome_id?: string | null
          primary_question_type?: string | null
          secondary_question_type?: string | null
          similarity_max_score?: number | null
          status?: string
          subject_id: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Update: {
          cognitive_type?: string | null
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          constraints?: Json
          created_at?: string
          created_by?: string | null
          curriculum_version_id?: string | null
          desired_count?: number
          difficulty?: string | null
          generation_instructions?: string | null
          grade_level?: number
          id?: string
          is_new_generation?: boolean | null
          max_solve_time_seconds?: number | null
          min_solve_time_seconds?: number | null
          originality_min_score?: number | null
          outcome_id?: string | null
          primary_question_type?: string | null
          secondary_question_type?: string | null
          similarity_max_score?: number | null
          status?: string
          subject_id?: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_generation_specs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_dispatches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_generation_specs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["dispatch_id"]
          },
          {
            foreignKeyName: "ai_generation_specs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["request_id"]
          },
          {
            foreignKeyName: "ai_generation_specs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_generation_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_generation_specs_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_generation_specs_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_generation_specs_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_generation_specs_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_generation_specs_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_jobs: {
        Row: {
          actual_cost: number | null
          attempt_count: number
          claim_token: string | null
          claimed_at: string | null
          claimed_by: string | null
          competition_factory_dispatch_id: string | null
          competition_generation_request_id: string | null
          completed_at: string | null
          created_at: string
          error_code: string | null
          error_message: string | null
          estimated_cost: number | null
          generation_spec_id: string | null
          heartbeat_at: string | null
          id: string
          import_batch_id: string | null
          input_data: Json
          job_type: string
          lease_expires_at: string | null
          max_attempts: number
          output_data: Json | null
          parent_job_id: string | null
          source_id: string | null
          started_at: string | null
          status: string
          updated_at: string
          workflow_id: string | null
        }
        Insert: {
          actual_cost?: number | null
          attempt_count?: number
          claim_token?: string | null
          claimed_at?: string | null
          claimed_by?: string | null
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          completed_at?: string | null
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          estimated_cost?: number | null
          generation_spec_id?: string | null
          heartbeat_at?: string | null
          id?: string
          import_batch_id?: string | null
          input_data?: Json
          job_type: string
          lease_expires_at?: string | null
          max_attempts?: number
          output_data?: Json | null
          parent_job_id?: string | null
          source_id?: string | null
          started_at?: string | null
          status?: string
          updated_at?: string
          workflow_id?: string | null
        }
        Update: {
          actual_cost?: number | null
          attempt_count?: number
          claim_token?: string | null
          claimed_at?: string | null
          claimed_by?: string | null
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          completed_at?: string | null
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          estimated_cost?: number | null
          generation_spec_id?: string | null
          heartbeat_at?: string | null
          id?: string
          import_batch_id?: string | null
          input_data?: Json
          job_type?: string
          lease_expires_at?: string | null
          max_attempts?: number
          output_data?: Json | null
          parent_job_id?: string | null
          source_id?: string | null
          started_at?: string | null
          status?: string
          updated_at?: string
          workflow_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_jobs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_dispatches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_jobs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["dispatch_id"]
          },
          {
            foreignKeyName: "ai_jobs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["request_id"]
          },
          {
            foreignKeyName: "ai_jobs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_generation_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_jobs_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_jobs_import_batch_id_fkey"
            columns: ["import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_jobs_parent_job_id_fkey"
            columns: ["parent_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_jobs_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "question_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_jobs_workflow_id_fkey"
            columns: ["workflow_id"]
            isOneToOne: false
            referencedRelation: "ai_workflows"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_originality_reviews: {
        Row: {
          concept_similarity_score: number | null
          confidence_score: number
          copyright_risk_level: string
          created_at: string
          evidence: Json
          exact_similarity_score: number | null
          highest_similarity_score: number
          highest_similarity_type: string | null
          id: string
          matched_question_id: string | null
          matched_source_id: string | null
          matched_staging_id: string | null
          metadata: Json
          model_name: string | null
          originality_score: number
          prompt_version: string | null
          provider_name: string | null
          review_summary: string | null
          reviewer_number: number
          semantic_similarity_score: number | null
          solution_path_copy_risk: boolean
          solution_path_similarity_score: number | null
          structural_similarity_score: number | null
          superficial_rewrite_detected: boolean
          template_copy_detected: boolean
          text_similarity_score: number | null
          verification_run_id: string
        }
        Insert: {
          concept_similarity_score?: number | null
          confidence_score: number
          copyright_risk_level?: string
          created_at?: string
          evidence?: Json
          exact_similarity_score?: number | null
          highest_similarity_score: number
          highest_similarity_type?: string | null
          id?: string
          matched_question_id?: string | null
          matched_source_id?: string | null
          matched_staging_id?: string | null
          metadata?: Json
          model_name?: string | null
          originality_score: number
          prompt_version?: string | null
          provider_name?: string | null
          review_summary?: string | null
          reviewer_number: number
          semantic_similarity_score?: number | null
          solution_path_copy_risk?: boolean
          solution_path_similarity_score?: number | null
          structural_similarity_score?: number | null
          superficial_rewrite_detected?: boolean
          template_copy_detected?: boolean
          text_similarity_score?: number | null
          verification_run_id: string
        }
        Update: {
          concept_similarity_score?: number | null
          confidence_score?: number
          copyright_risk_level?: string
          created_at?: string
          evidence?: Json
          exact_similarity_score?: number | null
          highest_similarity_score?: number
          highest_similarity_type?: string | null
          id?: string
          matched_question_id?: string | null
          matched_source_id?: string | null
          matched_staging_id?: string | null
          metadata?: Json
          model_name?: string | null
          originality_score?: number
          prompt_version?: string | null
          provider_name?: string | null
          review_summary?: string | null
          reviewer_number?: number
          semantic_similarity_score?: number | null
          solution_path_copy_risk?: boolean
          solution_path_similarity_score?: number | null
          structural_similarity_score?: number | null
          superficial_rewrite_detected?: boolean
          template_copy_detected?: boolean
          text_similarity_score?: number | null
          verification_run_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_originality_reviews_matched_question_id_fkey"
            columns: ["matched_question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_originality_reviews_matched_question_id_fkey"
            columns: ["matched_question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_originality_reviews_matched_question_id_fkey"
            columns: ["matched_question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_originality_reviews_matched_source_id_fkey"
            columns: ["matched_source_id"]
            isOneToOne: false
            referencedRelation: "question_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_originality_reviews_matched_staging_id_fkey"
            columns: ["matched_staging_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_originality_reviews_verification_run_id_fkey"
            columns: ["verification_run_id"]
            isOneToOne: false
            referencedRelation: "ai_originality_verification_overview"
            referencedColumns: ["verification_run_id"]
          },
          {
            foreignKeyName: "ai_originality_reviews_verification_run_id_fkey"
            columns: ["verification_run_id"]
            isOneToOne: false
            referencedRelation: "ai_originality_verification_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_originality_verification_runs: {
        Row: {
          ai_job_id: string | null
          consensus_originality_score: number | null
          copyright_risk_level: string
          created_at: string
          critical_similarity_score: number
          generation_spec_id: string | null
          highest_detected_similarity_score: number | null
          highest_similarity_type: string | null
          human_decision: string | null
          human_review_required: boolean
          human_reviewed_at: string | null
          human_reviewed_by: string | null
          id: string
          maximum_similarity_score: number
          metadata: Json
          minimum_confidence: number
          minimum_originality_score: number
          staging_question_id: string
          status: string
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          consensus_originality_score?: number | null
          copyright_risk_level?: string
          created_at?: string
          critical_similarity_score?: number
          generation_spec_id?: string | null
          highest_detected_similarity_score?: number | null
          highest_similarity_type?: string | null
          human_decision?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          maximum_similarity_score?: number
          metadata?: Json
          minimum_confidence?: number
          minimum_originality_score?: number
          staging_question_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          consensus_originality_score?: number | null
          copyright_risk_level?: string
          created_at?: string
          critical_similarity_score?: number
          generation_spec_id?: string | null
          highest_detected_similarity_score?: number | null
          highest_similarity_type?: string | null
          human_decision?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          maximum_similarity_score?: number
          metadata?: Json
          minimum_confidence?: number
          minimum_originality_score?: number
          staging_question_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_originality_verification_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_originality_verification_runs_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_originality_verification_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_quality_thresholds: {
        Row: {
          created_at: string
          grade_level: number | null
          id: string
          is_active: boolean
          is_blocking: boolean
          max_score: number | null
          min_score: number | null
          name: string
          notes: string | null
          scope_type: string
          subject_id: string | null
          threshold_code: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          grade_level?: number | null
          id?: string
          is_active?: boolean
          is_blocking?: boolean
          max_score?: number | null
          min_score?: number | null
          name: string
          notes?: string | null
          scope_type?: string
          subject_id?: string | null
          threshold_code: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          grade_level?: number | null
          id?: string
          is_active?: boolean
          is_blocking?: boolean
          max_score?: number | null
          min_score?: number | null
          name?: string
          notes?: string | null
          scope_type?: string
          subject_id?: string | null
          threshold_code?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_quality_thresholds_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_final_reviews: {
        Row: {
          decision: string
          id: string
          metadata: Json
          promoted_question_id: string | null
          readiness_run_id: string | null
          review_notes: string | null
          reviewed_at: string
          reviewed_by: string
          staging_question_id: string
        }
        Insert: {
          decision: string
          id?: string
          metadata?: Json
          promoted_question_id?: string | null
          readiness_run_id?: string | null
          review_notes?: string | null
          reviewed_at?: string
          reviewed_by: string
          staging_question_id: string
        }
        Update: {
          decision?: string
          id?: string
          metadata?: Json
          promoted_question_id?: string | null
          readiness_run_id?: string | null
          review_notes?: string | null
          reviewed_at?: string
          reviewed_by?: string
          staging_question_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_final_reviews_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_readiness_run_id_fkey"
            columns: ["readiness_run_id"]
            isOneToOne: false
            referencedRelation: "ai_question_readiness_overview"
            referencedColumns: ["readiness_run_id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_readiness_run_id_fkey"
            columns: ["readiness_run_id"]
            isOneToOne: false
            referencedRelation: "ai_question_readiness_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_quality_reviews: {
        Row: {
          age_grade_language_score: number
          age_inappropriate_language: boolean
          ambiguous_wording: boolean
          clarity_score: number
          cognitive_fit_score: number | null
          confidence_score: number
          created_at: string
          difficulty_fit_score: number | null
          factual_error_detected: boolean
          grammar_problem_detected: boolean
          id: string
          language_score: number
          metadata: Json
          misleading_option_risk: boolean
          missing_information_detected: boolean
          model_name: string | null
          multiple_correct_answer_risk: boolean
          no_correct_answer_risk: boolean
          option_quality_score: number
          overall_quality_score: number
          problems: Json
          prompt_version: string | null
          provider_name: string | null
          quality_run_id: string
          question_type_fit_score: number | null
          review_summary: string | null
          reviewer_number: number
          scientific_accuracy_score: number
          scientific_error_detected: boolean
          suggested_cognitive_type: string | null
          suggested_difficulty: string | null
          suggested_primary_question_type: string | null
          suggestions: Json
          unnecessary_information_problem: boolean
        }
        Insert: {
          age_grade_language_score: number
          age_inappropriate_language?: boolean
          ambiguous_wording?: boolean
          clarity_score: number
          cognitive_fit_score?: number | null
          confidence_score: number
          created_at?: string
          difficulty_fit_score?: number | null
          factual_error_detected?: boolean
          grammar_problem_detected?: boolean
          id?: string
          language_score: number
          metadata?: Json
          misleading_option_risk?: boolean
          missing_information_detected?: boolean
          model_name?: string | null
          multiple_correct_answer_risk?: boolean
          no_correct_answer_risk?: boolean
          option_quality_score: number
          overall_quality_score: number
          problems?: Json
          prompt_version?: string | null
          provider_name?: string | null
          quality_run_id: string
          question_type_fit_score?: number | null
          review_summary?: string | null
          reviewer_number: number
          scientific_accuracy_score: number
          scientific_error_detected?: boolean
          suggested_cognitive_type?: string | null
          suggested_difficulty?: string | null
          suggested_primary_question_type?: string | null
          suggestions?: Json
          unnecessary_information_problem?: boolean
        }
        Update: {
          age_grade_language_score?: number
          age_inappropriate_language?: boolean
          ambiguous_wording?: boolean
          clarity_score?: number
          cognitive_fit_score?: number | null
          confidence_score?: number
          created_at?: string
          difficulty_fit_score?: number | null
          factual_error_detected?: boolean
          grammar_problem_detected?: boolean
          id?: string
          language_score?: number
          metadata?: Json
          misleading_option_risk?: boolean
          missing_information_detected?: boolean
          model_name?: string | null
          multiple_correct_answer_risk?: boolean
          no_correct_answer_risk?: boolean
          option_quality_score?: number
          overall_quality_score?: number
          problems?: Json
          prompt_version?: string | null
          provider_name?: string | null
          quality_run_id?: string
          question_type_fit_score?: number | null
          review_summary?: string | null
          reviewer_number?: number
          scientific_accuracy_score?: number
          scientific_error_detected?: boolean
          suggested_cognitive_type?: string | null
          suggested_difficulty?: string | null
          suggested_primary_question_type?: string | null
          suggestions?: Json
          unnecessary_information_problem?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_quality_reviews_quality_run_id_fkey"
            columns: ["quality_run_id"]
            isOneToOne: false
            referencedRelation: "ai_question_quality_overview"
            referencedColumns: ["quality_run_id"]
          },
          {
            foreignKeyName: "ai_question_quality_reviews_quality_run_id_fkey"
            columns: ["quality_run_id"]
            isOneToOne: false
            referencedRelation: "ai_question_quality_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_quality_runs: {
        Row: {
          ai_job_id: string | null
          consensus_quality_score: number | null
          created_at: string
          generation_spec_id: string | null
          human_decision: string | null
          human_review_required: boolean
          human_reviewed_at: string | null
          human_reviewed_by: string | null
          id: string
          metadata: Json
          minimum_confidence: number
          minimum_quality_score: number
          staging_question_id: string
          status: string
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          consensus_quality_score?: number | null
          created_at?: string
          generation_spec_id?: string | null
          human_decision?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          minimum_confidence?: number
          minimum_quality_score?: number
          staging_question_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          consensus_quality_score?: number | null
          created_at?: string
          generation_spec_id?: string | null
          human_decision?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          minimum_confidence?: number
          minimum_quality_score?: number
          staging_question_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_quality_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_quality_runs_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_quality_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_readiness_runs: {
        Row: {
          ai_job_id: string | null
          answer_status: string | null
          answer_verification_passed: boolean
          blocking_reasons: Json
          commercial_clearance_status: string | null
          commercial_ready: boolean
          created_at: string
          curriculum_fit_passed: boolean
          curriculum_status: string | null
          evaluated_at: string
          evaluated_by: string | null
          generation_spec_id: string | null
          id: string
          metadata: Json
          originality_status: string | null
          originality_verification_passed: boolean
          quality_status: string | null
          question_quality_passed: boolean
          readiness_score: number | null
          readiness_status: string
          solve_time_status: string | null
          solve_time_verification_passed: boolean
          staging_question_id: string
          updated_at: string
          warnings: Json
        }
        Insert: {
          ai_job_id?: string | null
          answer_status?: string | null
          answer_verification_passed?: boolean
          blocking_reasons?: Json
          commercial_clearance_status?: string | null
          commercial_ready?: boolean
          created_at?: string
          curriculum_fit_passed?: boolean
          curriculum_status?: string | null
          evaluated_at?: string
          evaluated_by?: string | null
          generation_spec_id?: string | null
          id?: string
          metadata?: Json
          originality_status?: string | null
          originality_verification_passed?: boolean
          quality_status?: string | null
          question_quality_passed?: boolean
          readiness_score?: number | null
          readiness_status?: string
          solve_time_status?: string | null
          solve_time_verification_passed?: boolean
          staging_question_id: string
          updated_at?: string
          warnings?: Json
        }
        Update: {
          ai_job_id?: string | null
          answer_status?: string | null
          answer_verification_passed?: boolean
          blocking_reasons?: Json
          commercial_clearance_status?: string | null
          commercial_ready?: boolean
          created_at?: string
          curriculum_fit_passed?: boolean
          curriculum_status?: string | null
          evaluated_at?: string
          evaluated_by?: string | null
          generation_spec_id?: string | null
          id?: string
          metadata?: Json
          originality_status?: string | null
          originality_verification_passed?: boolean
          quality_status?: string | null
          question_quality_passed?: boolean
          readiness_score?: number | null
          readiness_status?: string
          solve_time_status?: string | null
          solve_time_verification_passed?: boolean
          staging_question_id?: string
          updated_at?: string
          warnings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_readiness_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_readiness_runs_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_readiness_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_staging: {
        Row: {
          ai_job_id: string | null
          answer_confidence: number | null
          classification_confidence: number | null
          commercial_use_allowed: boolean
          competition_factory_dispatch_id: string | null
          competition_generation_request_id: string | null
          copyright_risk_level: string
          created_at: string
          exam_track: string | null
          extraction_confidence: number | null
          final_question_id: string | null
          generation_spec_id: string | null
          grade_drift_detected: boolean
          grade_fit_score: number | null
          grade_level: number | null
          id: string
          import_batch_id: string | null
          legacy_question_key: string | null
          legacy_taxonomy_id: string | null
          license_status: string
          metadata: Json
          option_a: string | null
          option_b: string | null
          option_c: string | null
          option_d: string | null
          option_e: string | null
          originality_score: number | null
          outcome_drift_detected: boolean
          outcome_fit_score: number | null
          ownership_status: string
          prerequisite_violation: boolean
          proposed_cognitive_type: string | null
          proposed_correct_answer: string | null
          proposed_curriculum_version_id: string | null
          proposed_difficulty: string | null
          proposed_has_visual: boolean | null
          proposed_is_new_generation: boolean | null
          proposed_primary_question_type: string | null
          proposed_quality_level: string | null
          proposed_question_code: string | null
          proposed_secondary_question_type: string | null
          proposed_solve_time_seconds: number | null
          proposed_subtopic_id: string | null
          proposed_topic_id: string | null
          question_text: string | null
          source_id: string | null
          source_page_number: number | null
          source_question_number: number | null
          source_test_code: string | null
          source_test_number: number | null
          staging_source: string
          staging_status: string
          subject_id: string | null
          subtopic_fit_score: number | null
          topic_drift_detected: boolean
          topic_fit_score: number | null
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          answer_confidence?: number | null
          classification_confidence?: number | null
          commercial_use_allowed?: boolean
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          copyright_risk_level?: string
          created_at?: string
          exam_track?: string | null
          extraction_confidence?: number | null
          final_question_id?: string | null
          generation_spec_id?: string | null
          grade_drift_detected?: boolean
          grade_fit_score?: number | null
          grade_level?: number | null
          id?: string
          import_batch_id?: string | null
          legacy_question_key?: string | null
          legacy_taxonomy_id?: string | null
          license_status?: string
          metadata?: Json
          option_a?: string | null
          option_b?: string | null
          option_c?: string | null
          option_d?: string | null
          option_e?: string | null
          originality_score?: number | null
          outcome_drift_detected?: boolean
          outcome_fit_score?: number | null
          ownership_status?: string
          prerequisite_violation?: boolean
          proposed_cognitive_type?: string | null
          proposed_correct_answer?: string | null
          proposed_curriculum_version_id?: string | null
          proposed_difficulty?: string | null
          proposed_has_visual?: boolean | null
          proposed_is_new_generation?: boolean | null
          proposed_primary_question_type?: string | null
          proposed_quality_level?: string | null
          proposed_question_code?: string | null
          proposed_secondary_question_type?: string | null
          proposed_solve_time_seconds?: number | null
          proposed_subtopic_id?: string | null
          proposed_topic_id?: string | null
          question_text?: string | null
          source_id?: string | null
          source_page_number?: number | null
          source_question_number?: number | null
          source_test_code?: string | null
          source_test_number?: number | null
          staging_source: string
          staging_status?: string
          subject_id?: string | null
          subtopic_fit_score?: number | null
          topic_drift_detected?: boolean
          topic_fit_score?: number | null
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          answer_confidence?: number | null
          classification_confidence?: number | null
          commercial_use_allowed?: boolean
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          copyright_risk_level?: string
          created_at?: string
          exam_track?: string | null
          extraction_confidence?: number | null
          final_question_id?: string | null
          generation_spec_id?: string | null
          grade_drift_detected?: boolean
          grade_fit_score?: number | null
          grade_level?: number | null
          id?: string
          import_batch_id?: string | null
          legacy_question_key?: string | null
          legacy_taxonomy_id?: string | null
          license_status?: string
          metadata?: Json
          option_a?: string | null
          option_b?: string | null
          option_c?: string | null
          option_d?: string | null
          option_e?: string | null
          originality_score?: number | null
          outcome_drift_detected?: boolean
          outcome_fit_score?: number | null
          ownership_status?: string
          prerequisite_violation?: boolean
          proposed_cognitive_type?: string | null
          proposed_correct_answer?: string | null
          proposed_curriculum_version_id?: string | null
          proposed_difficulty?: string | null
          proposed_has_visual?: boolean | null
          proposed_is_new_generation?: boolean | null
          proposed_primary_question_type?: string | null
          proposed_quality_level?: string | null
          proposed_question_code?: string | null
          proposed_secondary_question_type?: string | null
          proposed_solve_time_seconds?: number | null
          proposed_subtopic_id?: string | null
          proposed_topic_id?: string | null
          question_text?: string | null
          source_id?: string | null
          source_page_number?: number | null
          source_question_number?: number | null
          source_test_code?: string | null
          source_test_number?: number | null
          staging_source?: string
          staging_status?: string
          subject_id?: string | null
          subtopic_fit_score?: number | null
          topic_drift_detected?: boolean
          topic_fit_score?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_staging_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_dispatches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["dispatch_id"]
          },
          {
            foreignKeyName: "ai_question_staging_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["request_id"]
          },
          {
            foreignKeyName: "ai_question_staging_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_generation_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_final_question_id_fkey"
            columns: ["final_question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_question_staging_final_question_id_fkey"
            columns: ["final_question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_question_staging_final_question_id_fkey"
            columns: ["final_question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_import_batch_id_fkey"
            columns: ["import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_legacy_taxonomy_id_fkey"
            columns: ["legacy_taxonomy_id"]
            isOneToOne: false
            referencedRelation: "legacy_taxonomy"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_proposed_curriculum_version_id_fkey"
            columns: ["proposed_curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_proposed_subtopic_id_fkey"
            columns: ["proposed_subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_proposed_topic_id_fkey"
            columns: ["proposed_topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "question_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_staging_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_solve_time_reviews: {
        Row: {
          calculation_details: Json
          calculation_load: string | null
          calculation_seconds: number
          calculation_step_count: number | null
          confidence_score: number
          created_at: string
          diagram_count: number | null
          formula_count: number | null
          graph_count: number | null
          id: string
          metadata: Json
          model_name: string | null
          option_reading_load: number | null
          other_seconds: number
          prompt_version: string | null
          provider_name: string | null
          reading_load: string | null
          reading_seconds: number
          reasoning_load: string | null
          reasoning_seconds: number
          reasoning_step_count: number | null
          recommended_race_limit_seconds: number
          review_summary: string | null
          reviewer_number: number
          table_count: number | null
          text_length_estimate: number | null
          total_seconds: number
          verification_run_id: string
          visual_analysis_seconds: number
          visual_count: number | null
          visual_load: string | null
        }
        Insert: {
          calculation_details?: Json
          calculation_load?: string | null
          calculation_seconds?: number
          calculation_step_count?: number | null
          confidence_score: number
          created_at?: string
          diagram_count?: number | null
          formula_count?: number | null
          graph_count?: number | null
          id?: string
          metadata?: Json
          model_name?: string | null
          option_reading_load?: number | null
          other_seconds?: number
          prompt_version?: string | null
          provider_name?: string | null
          reading_load?: string | null
          reading_seconds?: number
          reasoning_load?: string | null
          reasoning_seconds?: number
          reasoning_step_count?: number | null
          recommended_race_limit_seconds: number
          review_summary?: string | null
          reviewer_number: number
          table_count?: number | null
          text_length_estimate?: number | null
          total_seconds: number
          verification_run_id: string
          visual_analysis_seconds?: number
          visual_count?: number | null
          visual_load?: string | null
        }
        Update: {
          calculation_details?: Json
          calculation_load?: string | null
          calculation_seconds?: number
          calculation_step_count?: number | null
          confidence_score?: number
          created_at?: string
          diagram_count?: number | null
          formula_count?: number | null
          graph_count?: number | null
          id?: string
          metadata?: Json
          model_name?: string | null
          option_reading_load?: number | null
          other_seconds?: number
          prompt_version?: string | null
          provider_name?: string | null
          reading_load?: string | null
          reading_seconds?: number
          reasoning_load?: string | null
          reasoning_seconds?: number
          reasoning_step_count?: number | null
          recommended_race_limit_seconds?: number
          review_summary?: string | null
          reviewer_number?: number
          table_count?: number | null
          text_length_estimate?: number | null
          total_seconds?: number
          verification_run_id?: string
          visual_analysis_seconds?: number
          visual_count?: number | null
          visual_load?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_solve_time_reviews_verification_run_id_fkey"
            columns: ["verification_run_id"]
            isOneToOne: false
            referencedRelation: "ai_solve_time_verification_overview"
            referencedColumns: ["verification_run_id"]
          },
          {
            foreignKeyName: "ai_solve_time_reviews_verification_run_id_fkey"
            columns: ["verification_run_id"]
            isOneToOne: false
            referencedRelation: "ai_solve_time_verification_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_solve_time_verification_runs: {
        Row: {
          ai_job_id: string | null
          consensus_calculation_seconds: number | null
          consensus_other_seconds: number | null
          consensus_reading_seconds: number | null
          consensus_reasoning_seconds: number | null
          consensus_total_seconds: number | null
          consensus_visual_seconds: number | null
          created_at: string
          generation_spec_id: string | null
          human_decision: string | null
          human_race_limit_seconds: number | null
          human_review_required: boolean
          human_reviewed_at: string | null
          human_reviewed_by: string | null
          human_total_seconds: number | null
          id: string
          max_producer_difference_percent: number
          max_reviewer_difference_percent: number
          metadata: Json
          minimum_confidence: number
          producer_difference_percent: number | null
          producer_difference_seconds: number | null
          producer_estimated_total_seconds: number | null
          recommended_race_limit_seconds: number | null
          requested_max_seconds: number | null
          requested_min_seconds: number | null
          reviewer_difference_percent: number | null
          reviewer_difference_seconds: number | null
          staging_question_id: string
          status: string
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          consensus_calculation_seconds?: number | null
          consensus_other_seconds?: number | null
          consensus_reading_seconds?: number | null
          consensus_reasoning_seconds?: number | null
          consensus_total_seconds?: number | null
          consensus_visual_seconds?: number | null
          created_at?: string
          generation_spec_id?: string | null
          human_decision?: string | null
          human_race_limit_seconds?: number | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          human_total_seconds?: number | null
          id?: string
          max_producer_difference_percent?: number
          max_reviewer_difference_percent?: number
          metadata?: Json
          minimum_confidence?: number
          producer_difference_percent?: number | null
          producer_difference_seconds?: number | null
          producer_estimated_total_seconds?: number | null
          recommended_race_limit_seconds?: number | null
          requested_max_seconds?: number | null
          requested_min_seconds?: number | null
          reviewer_difference_percent?: number | null
          reviewer_difference_seconds?: number | null
          staging_question_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          consensus_calculation_seconds?: number | null
          consensus_other_seconds?: number | null
          consensus_reading_seconds?: number | null
          consensus_reasoning_seconds?: number | null
          consensus_total_seconds?: number | null
          consensus_visual_seconds?: number | null
          created_at?: string
          generation_spec_id?: string | null
          human_decision?: string | null
          human_race_limit_seconds?: number | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          human_total_seconds?: number | null
          id?: string
          max_producer_difference_percent?: number
          max_reviewer_difference_percent?: number
          metadata?: Json
          minimum_confidence?: number
          producer_difference_percent?: number | null
          producer_difference_seconds?: number | null
          producer_estimated_total_seconds?: number | null
          recommended_race_limit_seconds?: number | null
          requested_max_seconds?: number | null
          requested_min_seconds?: number | null
          reviewer_difference_percent?: number | null
          reviewer_difference_seconds?: number | null
          staging_question_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_solve_time_verification_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_solve_time_verification_runs_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_solve_time_verification_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_teacher_correction_proposals: {
        Row: {
          applied_at: string | null
          applied_by: string | null
          applied_to_staging: boolean
          change_reasons: Json
          change_summary: string | null
          confidence_score: number
          created_at: string
          human_review_required: boolean
          id: string
          metadata: Json
          model_name: string | null
          prompt_version: string | null
          proposed_correct_answer: string | null
          proposed_option_a: string | null
          proposed_option_b: string | null
          proposed_option_c: string | null
          proposed_option_d: string | null
          proposed_option_e: string | null
          proposed_question_text: string | null
          proposed_solution: Json
          provider_name: string | null
          requires_recheck: boolean
          review_run_id: string
          source_review_id: string | null
          staging_question_id: string
          status: string
        }
        Insert: {
          applied_at?: string | null
          applied_by?: string | null
          applied_to_staging?: boolean
          change_reasons?: Json
          change_summary?: string | null
          confidence_score: number
          created_at?: string
          human_review_required?: boolean
          id?: string
          metadata?: Json
          model_name?: string | null
          prompt_version?: string | null
          proposed_correct_answer?: string | null
          proposed_option_a?: string | null
          proposed_option_b?: string | null
          proposed_option_c?: string | null
          proposed_option_d?: string | null
          proposed_option_e?: string | null
          proposed_question_text?: string | null
          proposed_solution?: Json
          provider_name?: string | null
          requires_recheck?: boolean
          review_run_id: string
          source_review_id?: string | null
          staging_question_id: string
          status?: string
        }
        Update: {
          applied_at?: string | null
          applied_by?: string | null
          applied_to_staging?: boolean
          change_reasons?: Json
          change_summary?: string | null
          confidence_score?: number
          created_at?: string
          human_review_required?: boolean
          id?: string
          metadata?: Json
          model_name?: string | null
          prompt_version?: string | null
          proposed_correct_answer?: string | null
          proposed_option_a?: string | null
          proposed_option_b?: string | null
          proposed_option_c?: string | null
          proposed_option_d?: string | null
          proposed_option_e?: string | null
          proposed_question_text?: string | null
          proposed_solution?: Json
          provider_name?: string | null
          requires_recheck?: boolean
          review_run_id?: string
          source_review_id?: string | null
          staging_question_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_teacher_correction_proposals_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_overview"
            referencedColumns: ["review_run_id"]
          },
          {
            foreignKeyName: "ai_teacher_correction_proposals_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_correction_proposals_source_review_id_fkey"
            columns: ["source_review_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_reviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_correction_proposals_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_teacher_human_review_audit: {
        Row: {
          action: string
          correction_proposal_id: string | null
          created_at: string
          details: Json
          id: string
          notes: string | null
          performed_by: string
          review_run_id: string
          staging_question_id: string
        }
        Insert: {
          action: string
          correction_proposal_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          notes?: string | null
          performed_by: string
          review_run_id: string
          staging_question_id: string
        }
        Update: {
          action?: string
          correction_proposal_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          notes?: string | null
          performed_by?: string
          review_run_id?: string
          staging_question_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_teacher_human_review_audit_correction_proposal_id_fkey"
            columns: ["correction_proposal_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_correction_proposals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_human_review_audit_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_overview"
            referencedColumns: ["review_run_id"]
          },
          {
            foreignKeyName: "ai_teacher_human_review_audit_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_human_review_audit_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_teacher_review_issues: {
        Row: {
          blocks_publication: boolean
          correction_recommended: boolean
          created_at: string
          description: string
          evidence: Json
          field_name: string | null
          id: string
          issue_category: string
          issue_code: string
          review_id: string
          review_run_id: string
          severity: string
          staging_question_id: string
        }
        Insert: {
          blocks_publication?: boolean
          correction_recommended?: boolean
          created_at?: string
          description: string
          evidence?: Json
          field_name?: string | null
          id?: string
          issue_category: string
          issue_code: string
          review_id: string
          review_run_id: string
          severity: string
          staging_question_id: string
        }
        Update: {
          blocks_publication?: boolean
          correction_recommended?: boolean
          created_at?: string
          description?: string
          evidence?: Json
          field_name?: string | null
          id?: string
          issue_category?: string
          issue_code?: string
          review_id?: string
          review_run_id?: string
          severity?: string
          staging_question_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_teacher_review_issues_review_id_fkey"
            columns: ["review_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_reviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_review_issues_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_overview"
            referencedColumns: ["review_run_id"]
          },
          {
            foreignKeyName: "ai_teacher_review_issues_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_review_issues_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_teacher_review_profiles: {
        Row: {
          automatic_low_risk_threshold: number
          correction_allowed: boolean
          created_at: string
          description: string | null
          direct_publication_allowed: boolean
          id: string
          is_active: boolean
          metadata: Json
          minimum_confidence: number
          name: string
          profile_code: string
          profile_version: string
          prompt_version: string
          requires_answer_verification: boolean
          requires_curriculum_verification: boolean
          requires_grade_verification: boolean
          requires_language_verification: boolean
          requires_option_verification: boolean
          requires_originality_verification: boolean
          requires_solution_verification: boolean
          requires_solve_time_verification: boolean
          reviewer_role: string
          rules: Json
          subject_id: string
          updated_at: string
        }
        Insert: {
          automatic_low_risk_threshold?: number
          correction_allowed?: boolean
          created_at?: string
          description?: string | null
          direct_publication_allowed?: boolean
          id?: string
          is_active?: boolean
          metadata?: Json
          minimum_confidence?: number
          name: string
          profile_code: string
          profile_version?: string
          prompt_version?: string
          requires_answer_verification?: boolean
          requires_curriculum_verification?: boolean
          requires_grade_verification?: boolean
          requires_language_verification?: boolean
          requires_option_verification?: boolean
          requires_originality_verification?: boolean
          requires_solution_verification?: boolean
          requires_solve_time_verification?: boolean
          reviewer_role: string
          rules?: Json
          subject_id: string
          updated_at?: string
        }
        Update: {
          automatic_low_risk_threshold?: number
          correction_allowed?: boolean
          created_at?: string
          description?: string | null
          direct_publication_allowed?: boolean
          id?: string
          is_active?: boolean
          metadata?: Json
          minimum_confidence?: number
          name?: string
          profile_code?: string
          profile_version?: string
          prompt_version?: string
          requires_answer_verification?: boolean
          requires_curriculum_verification?: boolean
          requires_grade_verification?: boolean
          requires_language_verification?: boolean
          requires_option_verification?: boolean
          requires_originality_verification?: boolean
          requires_solution_verification?: boolean
          requires_solve_time_verification?: boolean
          reviewer_role?: string
          rules?: Json
          subject_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_teacher_review_profiles_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_teacher_review_runs: {
        Row: {
          ai_review_completed_at: string | null
          correction_completed: boolean
          correction_required: boolean
          created_at: string
          current_stage: string
          error_hunter_passed: boolean | null
          final_checker_passed: boolean | null
          human_decision: string | null
          human_review_reason: string | null
          human_review_required: boolean
          human_reviewed_at: string | null
          human_reviewed_by: string | null
          id: string
          metadata: Json
          overall_confidence: number | null
          overall_risk_level: string
          reviewer_disagreement_detected: boolean
          staging_question_id: string
          status: string
          subject_id: string
          subject_teacher_passed: boolean | null
          updated_at: string
        }
        Insert: {
          ai_review_completed_at?: string | null
          correction_completed?: boolean
          correction_required?: boolean
          created_at?: string
          current_stage?: string
          error_hunter_passed?: boolean | null
          final_checker_passed?: boolean | null
          human_decision?: string | null
          human_review_reason?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          overall_confidence?: number | null
          overall_risk_level?: string
          reviewer_disagreement_detected?: boolean
          staging_question_id: string
          status?: string
          subject_id: string
          subject_teacher_passed?: boolean | null
          updated_at?: string
        }
        Update: {
          ai_review_completed_at?: string | null
          correction_completed?: boolean
          correction_required?: boolean
          created_at?: string
          current_stage?: string
          error_hunter_passed?: boolean | null
          final_checker_passed?: boolean | null
          human_decision?: string | null
          human_review_reason?: string | null
          human_review_required?: boolean
          human_reviewed_at?: string | null
          human_reviewed_by?: string | null
          id?: string
          metadata?: Json
          overall_confidence?: number | null
          overall_risk_level?: string
          reviewer_disagreement_detected?: boolean
          staging_question_id?: string
          status?: string
          subject_id?: string
          subject_teacher_passed?: boolean | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_teacher_review_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_review_runs_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_teacher_reviews: {
        Row: {
          answer_is_correct: boolean | null
          calculation_accuracy: boolean | null
          confidence_score: number
          correction_required: boolean
          created_at: string
          curriculum_fit: boolean | null
          detected_errors: Json
          distractors_are_valid: boolean | null
          factual_accuracy: boolean | null
          grade_fit: boolean | null
          id: string
          language_fit: boolean | null
          metadata: Json
          model_name: string | null
          options_are_valid: boolean | null
          profile_id: string
          prompt_version: string | null
          provider_name: string | null
          question_is_complete: boolean | null
          question_is_unambiguous: boolean | null
          review_iteration: number
          review_run_id: string
          review_summary: string | null
          reviewer_number: number
          reviewer_role: string
          risk_level: string
          single_correct_answer: boolean | null
          solution_is_correct: boolean | null
          solve_time_is_reasonable: boolean | null
          staging_question_id: string
          terminology_fit: boolean | null
          unit_consistency: boolean | null
          verdict: string
          verification_details: Json
          warnings: Json
        }
        Insert: {
          answer_is_correct?: boolean | null
          calculation_accuracy?: boolean | null
          confidence_score: number
          correction_required?: boolean
          created_at?: string
          curriculum_fit?: boolean | null
          detected_errors?: Json
          distractors_are_valid?: boolean | null
          factual_accuracy?: boolean | null
          grade_fit?: boolean | null
          id?: string
          language_fit?: boolean | null
          metadata?: Json
          model_name?: string | null
          options_are_valid?: boolean | null
          profile_id: string
          prompt_version?: string | null
          provider_name?: string | null
          question_is_complete?: boolean | null
          question_is_unambiguous?: boolean | null
          review_iteration?: number
          review_run_id: string
          review_summary?: string | null
          reviewer_number?: number
          reviewer_role: string
          risk_level?: string
          single_correct_answer?: boolean | null
          solution_is_correct?: boolean | null
          solve_time_is_reasonable?: boolean | null
          staging_question_id: string
          terminology_fit?: boolean | null
          unit_consistency?: boolean | null
          verdict: string
          verification_details?: Json
          warnings?: Json
        }
        Update: {
          answer_is_correct?: boolean | null
          calculation_accuracy?: boolean | null
          confidence_score?: number
          correction_required?: boolean
          created_at?: string
          curriculum_fit?: boolean | null
          detected_errors?: Json
          distractors_are_valid?: boolean | null
          factual_accuracy?: boolean | null
          grade_fit?: boolean | null
          id?: string
          language_fit?: boolean | null
          metadata?: Json
          model_name?: string | null
          options_are_valid?: boolean | null
          profile_id?: string
          prompt_version?: string | null
          provider_name?: string | null
          question_is_complete?: boolean | null
          question_is_unambiguous?: boolean | null
          review_iteration?: number
          review_run_id?: string
          review_summary?: string | null
          reviewer_number?: number
          reviewer_role?: string
          risk_level?: string
          single_correct_answer?: boolean | null
          solution_is_correct?: boolean | null
          solve_time_is_reasonable?: boolean | null
          staging_question_id?: string
          terminology_fit?: boolean | null
          unit_consistency?: boolean | null
          verdict?: string
          verification_details?: Json
          warnings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "ai_teacher_reviews_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_reviews_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_overview"
            referencedColumns: ["review_run_id"]
          },
          {
            foreignKeyName: "ai_teacher_reviews_review_run_id_fkey"
            columns: ["review_run_id"]
            isOneToOne: false
            referencedRelation: "ai_teacher_review_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_reviews_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_validation_results: {
        Row: {
          ai_job_id: string | null
          created_at: string
          details: Json
          id: string
          model_name: string | null
          prompt_version: string | null
          provider_name: string | null
          result: string
          reviewed_by: string | null
          score: number | null
          staging_question_id: string
          summary: string | null
          validation_type: string
          validator_type: string
        }
        Insert: {
          ai_job_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          model_name?: string | null
          prompt_version?: string | null
          provider_name?: string | null
          result: string
          reviewed_by?: string | null
          score?: number | null
          staging_question_id: string
          summary?: string | null
          validation_type: string
          validator_type: string
        }
        Update: {
          ai_job_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          model_name?: string | null
          prompt_version?: string | null
          provider_name?: string | null
          result?: string
          reviewed_by?: string | null
          score?: number | null
          staging_question_id?: string
          summary?: string | null
          validation_type?: string
          validator_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_validation_results_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_validation_results_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_worker_candidate_results: {
        Row: {
          candidate_index: number
          candidate_key: string | null
          created_at: string
          id: string
          raw_candidate: Json
          staging_question_id: string | null
          updated_at: string
          validation_errors: Json
          validation_status: string
          validation_warnings: Json
          worker_output_id: string
        }
        Insert: {
          candidate_index: number
          candidate_key?: string | null
          created_at?: string
          id?: string
          raw_candidate: Json
          staging_question_id?: string | null
          updated_at?: string
          validation_errors?: Json
          validation_status?: string
          validation_warnings?: Json
          worker_output_id: string
        }
        Update: {
          candidate_index?: number
          candidate_key?: string | null
          created_at?: string
          id?: string
          raw_candidate?: Json
          staging_question_id?: string | null
          updated_at?: string
          validation_errors?: Json
          validation_status?: string
          validation_warnings?: Json
          worker_output_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_worker_candidate_results_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_worker_candidate_results_worker_output_id_fkey"
            columns: ["worker_output_id"]
            isOneToOne: false
            referencedRelation: "ai_worker_output_overview"
            referencedColumns: ["worker_output_id"]
          },
          {
            foreignKeyName: "ai_worker_candidate_results_worker_output_id_fkey"
            columns: ["worker_output_id"]
            isOneToOne: false
            referencedRelation: "ai_worker_outputs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_worker_outputs: {
        Row: {
          ai_job_id: string
          competition_factory_dispatch_id: string | null
          competition_generation_request_id: string | null
          created_at: string
          duplicate_question_count: number
          error_data: Json
          generation_spec_id: string | null
          id: string
          ingested_at: string | null
          inserted_question_count: number
          invalid_question_count: number
          metadata: Json
          model_name: string | null
          prompt_version: string | null
          provider_name: string | null
          raw_output: Json
          received_at: string
          received_question_count: number
          remaining_question_count: number
          requested_question_count: number | null
          retry_required: boolean
          status: string
          updated_at: string
          valid_question_count: number
          validated_at: string | null
          validation_summary: Json
          worker_version: string | null
        }
        Insert: {
          ai_job_id: string
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          created_at?: string
          duplicate_question_count?: number
          error_data?: Json
          generation_spec_id?: string | null
          id?: string
          ingested_at?: string | null
          inserted_question_count?: number
          invalid_question_count?: number
          metadata?: Json
          model_name?: string | null
          prompt_version?: string | null
          provider_name?: string | null
          raw_output: Json
          received_at?: string
          received_question_count?: number
          remaining_question_count?: number
          requested_question_count?: number | null
          retry_required?: boolean
          status?: string
          updated_at?: string
          valid_question_count?: number
          validated_at?: string | null
          validation_summary?: Json
          worker_version?: string | null
        }
        Update: {
          ai_job_id?: string
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          created_at?: string
          duplicate_question_count?: number
          error_data?: Json
          generation_spec_id?: string | null
          id?: string
          ingested_at?: string | null
          inserted_question_count?: number
          invalid_question_count?: number
          metadata?: Json
          model_name?: string | null
          prompt_version?: string | null
          provider_name?: string | null
          raw_output?: Json
          received_at?: string
          received_question_count?: number
          remaining_question_count?: number
          requested_question_count?: number | null
          retry_required?: boolean
          status?: string
          updated_at?: string
          valid_question_count?: number
          validated_at?: string | null
          validation_summary?: Json
          worker_version?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_worker_outputs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_dispatches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["dispatch_id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["request_id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_generation_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_workflow_steps: {
        Row: {
          agent_id: string | null
          configuration: Json
          created_at: string
          failure_action: string
          id: string
          is_required: boolean
          step_code: string
          step_order: number
          step_type: string
          workflow_id: string
        }
        Insert: {
          agent_id?: string | null
          configuration?: Json
          created_at?: string
          failure_action?: string
          id?: string
          is_required?: boolean
          step_code: string
          step_order: number
          step_type: string
          workflow_id: string
        }
        Update: {
          agent_id?: string | null
          configuration?: Json
          created_at?: string
          failure_action?: string
          id?: string
          is_required?: boolean
          step_code?: string
          step_order?: number
          step_type?: string
          workflow_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_workflow_steps_agent_id_fkey"
            columns: ["agent_id"]
            isOneToOne: false
            referencedRelation: "ai_agents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_workflow_steps_workflow_id_fkey"
            columns: ["workflow_id"]
            isOneToOne: false
            referencedRelation: "ai_workflows"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_workflows: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          updated_at: string
          workflow_code: string
          workflow_type: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          updated_at?: string
          workflow_code: string
          workflow_type: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          updated_at?: string
          workflow_code?: string
          workflow_type?: string
        }
        Relationships: []
      }
      annual_stock_targets: {
        Row: {
          base_target_count: number
          created_at: string
          curriculum_version_id: string
          easy_target_count: number | null
          grade_level: number
          hard_target_count: number | null
          id: string
          is_active: boolean
          medium_target_count: number | null
          metadata: Json
          notes: string | null
          stock_scope: string
          subject_id: string
          updated_at: string
          week: number
        }
        Insert: {
          base_target_count: number
          created_at?: string
          curriculum_version_id: string
          easy_target_count?: number | null
          grade_level: number
          hard_target_count?: number | null
          id?: string
          is_active?: boolean
          medium_target_count?: number | null
          metadata?: Json
          notes?: string | null
          stock_scope: string
          subject_id: string
          updated_at?: string
          week: number
        }
        Update: {
          base_target_count?: number
          created_at?: string
          curriculum_version_id?: string
          easy_target_count?: number | null
          grade_level?: number
          hard_target_count?: number | null
          id?: string
          is_active?: boolean
          medium_target_count?: number | null
          metadata?: Json
          notes?: string | null
          stock_scope?: string
          subject_id?: string
          updated_at?: string
          week?: number
        }
        Relationships: [
          {
            foreignKeyName: "annual_stock_targets_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "annual_stock_targets_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      characters: {
        Row: {
          character_code: string
          configuration: Json
          created_at: string
          description: string | null
          id: string
          image_key: string | null
          is_active: boolean
          name: string
          rarity: string
          sort_order: number
          unlock_type: string
          unlock_value: number | null
          updated_at: string
        }
        Insert: {
          character_code: string
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          image_key?: string | null
          is_active?: boolean
          name: string
          rarity?: string
          sort_order?: number
          unlock_type?: string
          unlock_value?: number | null
          updated_at?: string
        }
        Update: {
          character_code?: string
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          image_key?: string | null
          is_active?: boolean
          name?: string
          rarity?: string
          sort_order?: number
          unlock_type?: string
          unlock_value?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      commercial_question_clearance: {
        Row: {
          clearance_status: string
          copyright_review_passed: boolean
          created_at: string
          decision_reason: string | null
          highest_similarity_score: number | null
          id: string
          license_check_passed: boolean
          originality_check_passed: boolean
          originality_score: number | null
          ownership_check_passed: boolean
          quality_review_passed: boolean
          question_id: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          similarity_check_passed: boolean
          staging_question_id: string | null
          updated_at: string
        }
        Insert: {
          clearance_status?: string
          copyright_review_passed?: boolean
          created_at?: string
          decision_reason?: string | null
          highest_similarity_score?: number | null
          id?: string
          license_check_passed?: boolean
          originality_check_passed?: boolean
          originality_score?: number | null
          ownership_check_passed?: boolean
          quality_review_passed?: boolean
          question_id?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          similarity_check_passed?: boolean
          staging_question_id?: string | null
          updated_at?: string
        }
        Update: {
          clearance_status?: string
          copyright_review_passed?: boolean
          created_at?: string
          decision_reason?: string | null
          highest_similarity_score?: number | null
          id?: string
          license_check_passed?: boolean
          originality_check_passed?: boolean
          originality_score?: number | null
          ownership_check_passed?: boolean
          quality_review_passed?: boolean
          question_id?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          similarity_check_passed?: boolean
          staging_question_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "commercial_question_clearance_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "commercial_question_clearance_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "commercial_question_clearance_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commercial_question_clearance_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_ai_factory_dispatches: {
        Row: {
          ai_job_id: string | null
          analysis_run_id: string | null
          approved_at: string | null
          approved_by: string | null
          approved_count: number
          automatic_publication_allowed: boolean
          competition_generation_request_id: string
          copyright_blocked_count: number
          copyright_requirements: Json
          created_at: string
          curriculum_rejected_count: number
          curriculum_requirements: Json
          dispatch_code: string
          diversity_requirements: Json
          error_data: Json
          gap_item_id: string | null
          generated_count: number
          generation_requirements: Json
          generation_spec_id: string | null
          human_approved: boolean
          id: string
          metadata: Json
          production_promotion_allowed: boolean
          profile_id: string
          quality_requirements: Json
          rejected_count: number
          requested_question_count: number
          review_requirements: Json
          solve_time_rejected_count: number
          solve_time_requirements: Json
          staging_count: number
          status: string
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          analysis_run_id?: string | null
          approved_at?: string | null
          approved_by?: string | null
          approved_count?: number
          automatic_publication_allowed?: boolean
          competition_generation_request_id: string
          copyright_blocked_count?: number
          copyright_requirements?: Json
          created_at?: string
          curriculum_rejected_count?: number
          curriculum_requirements?: Json
          dispatch_code: string
          diversity_requirements?: Json
          error_data?: Json
          gap_item_id?: string | null
          generated_count?: number
          generation_requirements?: Json
          generation_spec_id?: string | null
          human_approved?: boolean
          id?: string
          metadata?: Json
          production_promotion_allowed?: boolean
          profile_id: string
          quality_requirements?: Json
          rejected_count?: number
          requested_question_count: number
          review_requirements?: Json
          solve_time_rejected_count?: number
          solve_time_requirements?: Json
          staging_count?: number
          status?: string
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          analysis_run_id?: string | null
          approved_at?: string | null
          approved_by?: string | null
          approved_count?: number
          automatic_publication_allowed?: boolean
          competition_generation_request_id?: string
          copyright_blocked_count?: number
          copyright_requirements?: Json
          created_at?: string
          curriculum_rejected_count?: number
          curriculum_requirements?: Json
          dispatch_code?: string
          diversity_requirements?: Json
          error_data?: Json
          gap_item_id?: string | null
          generated_count?: number
          generation_requirements?: Json
          generation_spec_id?: string | null
          human_approved?: boolean
          id?: string
          metadata?: Json
          production_promotion_allowed?: boolean
          profile_id?: string
          quality_requirements?: Json
          rejected_count?: number
          requested_question_count?: number
          review_requirements?: Json
          solve_time_rejected_count?: number
          solve_time_requirements?: Json
          staging_count?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "competition_ai_factory_dispat_competition_generation_reque_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: true
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["request_id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispat_competition_generation_reque_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: true
            referencedRelation: "competition_ai_generation_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_analysis_run_id_fkey"
            columns: ["analysis_run_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_analysis_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_gap_item_id_fkey"
            columns: ["gap_item_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_gap_item_id_fkey"
            columns: ["gap_item_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_overview"
            referencedColumns: ["gap_item_id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_overview"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_ai_generation_requests: {
        Row: {
          ai_job_id: string | null
          analysis_run_id: string | null
          approved_at: string | null
          approved_by: string | null
          approved_count: number
          copyright_requirements: Json
          created_at: string
          diversity_requirements: Json
          gap_item_id: string | null
          generated_count: number
          generation_requirements: Json
          generation_spec_id: string | null
          human_approval_received: boolean
          human_approval_required: boolean
          id: string
          metadata: Json
          notes: string | null
          profile_id: string
          quality_requirements: Json
          rejected_count: number
          request_code: string
          requested_question_count: number
          solve_time_requirements: Json
          staging_count: number
          status: string
          updated_at: string
        }
        Insert: {
          ai_job_id?: string | null
          analysis_run_id?: string | null
          approved_at?: string | null
          approved_by?: string | null
          approved_count?: number
          copyright_requirements?: Json
          created_at?: string
          diversity_requirements?: Json
          gap_item_id?: string | null
          generated_count?: number
          generation_requirements?: Json
          generation_spec_id?: string | null
          human_approval_received?: boolean
          human_approval_required?: boolean
          id?: string
          metadata?: Json
          notes?: string | null
          profile_id: string
          quality_requirements?: Json
          rejected_count?: number
          request_code: string
          requested_question_count: number
          solve_time_requirements?: Json
          staging_count?: number
          status?: string
          updated_at?: string
        }
        Update: {
          ai_job_id?: string | null
          analysis_run_id?: string | null
          approved_at?: string | null
          approved_by?: string | null
          approved_count?: number
          copyright_requirements?: Json
          created_at?: string
          diversity_requirements?: Json
          gap_item_id?: string | null
          generated_count?: number
          generation_requirements?: Json
          generation_spec_id?: string | null
          human_approval_received?: boolean
          human_approval_required?: boolean
          id?: string
          metadata?: Json
          notes?: string | null
          profile_id?: string
          quality_requirements?: Json
          rejected_count?: number
          request_code?: string
          requested_question_count?: number
          solve_time_requirements?: Json
          staging_count?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "competition_ai_generation_requests_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_generation_requests_analysis_run_id_fkey"
            columns: ["analysis_run_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_analysis_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_generation_requests_gap_item_id_fkey"
            columns: ["gap_item_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_generation_requests_gap_item_id_fkey"
            columns: ["gap_item_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_overview"
            referencedColumns: ["gap_item_id"]
          },
          {
            foreignKeyName: "competition_ai_generation_requests_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_generation_requests_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_overview"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "competition_ai_generation_requests_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_answers: {
        Row: {
          answer_received_at: string
          answer_result: string
          competition_id: string
          competition_question_id: string
          created_at: string
          deadline_at: string
          id: string
          points_awarded: number
          sent_at: string
          server_validated: boolean
          submitted_answer: string | null
          time_band_code: string | null
          time_band_name: string | null
          time_ms: number
          user_id: string
          validation_data: Json
        }
        Insert: {
          answer_received_at?: string
          answer_result: string
          competition_id: string
          competition_question_id: string
          created_at?: string
          deadline_at: string
          id?: string
          points_awarded?: number
          sent_at: string
          server_validated?: boolean
          submitted_answer?: string | null
          time_band_code?: string | null
          time_band_name?: string | null
          time_ms: number
          user_id: string
          validation_data?: Json
        }
        Update: {
          answer_received_at?: string
          answer_result?: string
          competition_id?: string
          competition_question_id?: string
          created_at?: string
          deadline_at?: string
          id?: string
          points_awarded?: number
          sent_at?: string
          server_validated?: boolean
          submitted_answer?: string | null
          time_band_code?: string | null
          time_band_name?: string | null
          time_ms?: number
          user_id?: string
          validation_data?: Json
        }
        Relationships: [
          {
            foreignKeyName: "competition_answers_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_answers_competition_question_id_fkey"
            columns: ["competition_question_id"]
            isOneToOne: false
            referencedRelation: "competition_questions"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_disconnects: {
        Row: {
          competition_id: string
          disconnect_reason: string | null
          disconnected_at: string
          duration_ms: number | null
          id: string
          metadata: Json
          reconnected_at: string | null
          user_id: string
        }
        Insert: {
          competition_id: string
          disconnect_reason?: string | null
          disconnected_at?: string
          duration_ms?: number | null
          id?: string
          metadata?: Json
          reconnected_at?: string | null
          user_id: string
        }
        Update: {
          competition_id?: string
          disconnect_reason?: string | null
          disconnected_at?: string
          duration_ms?: number | null
          id?: string
          metadata?: Json
          reconnected_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "competition_disconnects_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_players: {
        Row: {
          competition_id: string
          correct_count: number
          finished_at: string | null
          id: string
          joined_at: string
          metadata: Json
          pass_count: number
          player_slot: number
          ready_at: string | null
          status: string
          timeout_count: number
          total_points: number
          user_id: string
          wrong_count: number
        }
        Insert: {
          competition_id: string
          correct_count?: number
          finished_at?: string | null
          id?: string
          joined_at?: string
          metadata?: Json
          pass_count?: number
          player_slot: number
          ready_at?: string | null
          status?: string
          timeout_count?: number
          total_points?: number
          user_id: string
          wrong_count?: number
        }
        Update: {
          competition_id?: string
          correct_count?: number
          finished_at?: string | null
          id?: string
          joined_at?: string
          metadata?: Json
          pass_count?: number
          player_slot?: number
          ready_at?: string | null
          status?: string
          timeout_count?: number
          total_points?: number
          user_id?: string
          wrong_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "competition_players_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_point_changes: {
        Row: {
          change_type: string
          competition_id: string
          created_at: string
          id: string
          metadata: Json
          points_after: number | null
          points_before: number | null
          points_change: number
          reason_code: string | null
          rule_reference: Json
          user_id: string
        }
        Insert: {
          change_type?: string
          competition_id: string
          created_at?: string
          id?: string
          metadata?: Json
          points_after?: number | null
          points_before?: number | null
          points_change?: number
          reason_code?: string | null
          rule_reference?: Json
          user_id: string
        }
        Update: {
          change_type?: string
          competition_id?: string
          created_at?: string
          id?: string
          metadata?: Json
          points_after?: number | null
          points_before?: number | null
          points_change?: number
          reason_code?: string | null
          rule_reference?: Json
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "competition_point_changes_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_pool_analysis_runs: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string | null
          error_data: Json
          id: string
          metadata: Json
          requested_grade_level: number | null
          requested_profile_id: string | null
          requested_subject_id: string | null
          run_code: string
          run_type: string
          started_at: string | null
          status: string
          summary: Json
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          error_data?: Json
          id?: string
          metadata?: Json
          requested_grade_level?: number | null
          requested_profile_id?: string | null
          requested_subject_id?: string | null
          run_code: string
          run_type?: string
          started_at?: string | null
          status?: string
          summary?: Json
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          error_data?: Json
          id?: string
          metadata?: Json
          requested_grade_level?: number | null
          requested_profile_id?: string | null
          requested_subject_id?: string | null
          run_code?: string
          run_type?: string
          started_at?: string | null
          status?: string
          summary?: Json
        }
        Relationships: [
          {
            foreignKeyName: "competition_pool_analysis_runs_requested_profile_id_fkey"
            columns: ["requested_profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_overview"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "competition_pool_analysis_runs_requested_profile_id_fkey"
            columns: ["requested_profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_analysis_runs_requested_subject_id_fkey"
            columns: ["requested_subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_pool_gap_items: {
        Row: {
          analysis_run_id: string
          approved_active_questions: number
          buffer_target_count: number
          calculated_at: string
          copyright_analysis: Json
          copyright_blocked_questions: number
          diversity_analysis: Json
          diversity_rejected_questions: number
          gap_status: string
          id: string
          missing_question_count: number
          overused_questions: number
          profile_id: string
          quality_analysis: Json
          quality_rejected_questions: number
          questions_with_time_profile: number
          recommendation: Json
          scoring_ready_questions: number
          target_question_count: number
          time_profile_analysis: Json
          total_matching_questions: number
          urgency_score: number
          usable_question_count: number
          usage_analysis: Json
        }
        Insert: {
          analysis_run_id: string
          approved_active_questions?: number
          buffer_target_count?: number
          calculated_at?: string
          copyright_analysis?: Json
          copyright_blocked_questions?: number
          diversity_analysis?: Json
          diversity_rejected_questions?: number
          gap_status?: string
          id?: string
          missing_question_count?: number
          overused_questions?: number
          profile_id: string
          quality_analysis?: Json
          quality_rejected_questions?: number
          questions_with_time_profile?: number
          recommendation?: Json
          scoring_ready_questions?: number
          target_question_count: number
          time_profile_analysis?: Json
          total_matching_questions?: number
          urgency_score?: number
          usable_question_count?: number
          usage_analysis?: Json
        }
        Update: {
          analysis_run_id?: string
          approved_active_questions?: number
          buffer_target_count?: number
          calculated_at?: string
          copyright_analysis?: Json
          copyright_blocked_questions?: number
          diversity_analysis?: Json
          diversity_rejected_questions?: number
          gap_status?: string
          id?: string
          missing_question_count?: number
          overused_questions?: number
          profile_id?: string
          quality_analysis?: Json
          quality_rejected_questions?: number
          questions_with_time_profile?: number
          recommendation?: Json
          scoring_ready_questions?: number
          target_question_count?: number
          time_profile_analysis?: Json
          total_matching_questions?: number
          urgency_score?: number
          usable_question_count?: number
          usage_analysis?: Json
        }
        Relationships: [
          {
            foreignKeyName: "competition_pool_gap_items_analysis_run_id_fkey"
            columns: ["analysis_run_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_analysis_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_gap_items_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_gap_overview"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "competition_pool_gap_items_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_pool_profiles: {
        Row: {
          ai_generation_rules: Json
          calculation_load: string | null
          cognitive_level: string | null
          created_at: string
          curriculum_version_id: string | null
          description: string | null
          difficulty: string | null
          diversity_rules: Json
          grade_level: number
          id: string
          is_active: boolean
          max_solve_time_seconds: number | null
          max_uses_per_window: number
          metadata: Json
          min_solve_time_seconds: number | null
          minimum_safe_count: number
          name: string
          new_generation_required: boolean | null
          outcome_id: string | null
          preferred_buffer_percent: number
          priority: number
          profile_code: string
          question_type: string | null
          reading_load: string | null
          reasoning_load: string | null
          requires_diagram: boolean | null
          requires_graph: boolean | null
          requires_table: boolean | null
          requires_visual: boolean | null
          selection_rules: Json
          subject_id: string
          subtopic_id: string | null
          target_question_count: number
          topic_id: string | null
          updated_at: string
          usage_window_days: number
          visual_load: string | null
        }
        Insert: {
          ai_generation_rules?: Json
          calculation_load?: string | null
          cognitive_level?: string | null
          created_at?: string
          curriculum_version_id?: string | null
          description?: string | null
          difficulty?: string | null
          diversity_rules?: Json
          grade_level: number
          id?: string
          is_active?: boolean
          max_solve_time_seconds?: number | null
          max_uses_per_window?: number
          metadata?: Json
          min_solve_time_seconds?: number | null
          minimum_safe_count?: number
          name: string
          new_generation_required?: boolean | null
          outcome_id?: string | null
          preferred_buffer_percent?: number
          priority?: number
          profile_code: string
          question_type?: string | null
          reading_load?: string | null
          reasoning_load?: string | null
          requires_diagram?: boolean | null
          requires_graph?: boolean | null
          requires_table?: boolean | null
          requires_visual?: boolean | null
          selection_rules?: Json
          subject_id: string
          subtopic_id?: string | null
          target_question_count?: number
          topic_id?: string | null
          updated_at?: string
          usage_window_days?: number
          visual_load?: string | null
        }
        Update: {
          ai_generation_rules?: Json
          calculation_load?: string | null
          cognitive_level?: string | null
          created_at?: string
          curriculum_version_id?: string | null
          description?: string | null
          difficulty?: string | null
          diversity_rules?: Json
          grade_level?: number
          id?: string
          is_active?: boolean
          max_solve_time_seconds?: number | null
          max_uses_per_window?: number
          metadata?: Json
          min_solve_time_seconds?: number | null
          minimum_safe_count?: number
          name?: string
          new_generation_required?: boolean | null
          outcome_id?: string | null
          preferred_buffer_percent?: number
          priority?: number
          profile_code?: string
          question_type?: string | null
          reading_load?: string | null
          reasoning_load?: string | null
          requires_diagram?: boolean | null
          requires_graph?: boolean | null
          requires_table?: boolean | null
          requires_visual?: boolean | null
          selection_rules?: Json
          subject_id?: string
          subtopic_id?: string | null
          target_question_count?: number
          topic_id?: string | null
          updated_at?: string
          usage_window_days?: number
          visual_load?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "competition_pool_profiles_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_questions: {
        Row: {
          competition_id: string
          completed_at: string | null
          configuration: Json
          created_at: string
          deadline_at: string | null
          difficulty: string
          id: string
          question_id: string
          question_order: number
          released_at: string | null
          sent_at: string | null
          solve_time_profile_id: string | null
          time_limit_seconds: number | null
          timing_source: string | null
        }
        Insert: {
          competition_id: string
          completed_at?: string | null
          configuration?: Json
          created_at?: string
          deadline_at?: string | null
          difficulty: string
          id?: string
          question_id: string
          question_order: number
          released_at?: string | null
          sent_at?: string | null
          solve_time_profile_id?: string | null
          time_limit_seconds?: number | null
          timing_source?: string | null
        }
        Update: {
          competition_id?: string
          completed_at?: string | null
          configuration?: Json
          created_at?: string
          deadline_at?: string | null
          difficulty?: string
          id?: string
          question_id?: string
          question_order?: number
          released_at?: string | null
          sent_at?: string | null
          solve_time_profile_id?: string | null
          time_limit_seconds?: number | null
          timing_source?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "competition_questions_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_questions_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "competition_questions_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "competition_questions_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_questions_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["solve_time_profile_id"]
          },
          {
            foreignKeyName: "competition_questions_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_results: {
        Row: {
          calculated_at: string
          competition_id: string
          final_scoreboard: Json
          id: string
          metadata: Json
          player_results: Json
          point_changes: Json
          question_results: Json
          result_type: string
          scoring_snapshot: Json
          winner_user_id: string | null
        }
        Insert: {
          calculated_at?: string
          competition_id: string
          final_scoreboard?: Json
          id?: string
          metadata?: Json
          player_results?: Json
          point_changes?: Json
          question_results?: Json
          result_type: string
          scoring_snapshot?: Json
          winner_user_id?: string | null
        }
        Update: {
          calculated_at?: string
          competition_id?: string
          final_scoreboard?: Json
          id?: string
          metadata?: Json
          player_results?: Json
          point_changes?: Json
          question_results?: Json
          result_type?: string
          scoring_snapshot?: Json
          winner_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "competition_results_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: true
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
        ]
      }
      competitions: {
        Row: {
          competition_code: string
          competition_type: string
          completed_at: string | null
          configuration: Json
          created_at: string
          current_question_id: string | null
          current_question_order: number | null
          grade_level: number
          id: string
          question_count: number
          scoring_rule_set_id: string
          server_completed_at: string | null
          server_started_at: string | null
          started_at: string | null
          status: string
          subject_id: string | null
          updated_at: string
          winner_user_id: string | null
        }
        Insert: {
          competition_code: string
          competition_type?: string
          completed_at?: string | null
          configuration?: Json
          created_at?: string
          current_question_id?: string | null
          current_question_order?: number | null
          grade_level: number
          id?: string
          question_count: number
          scoring_rule_set_id: string
          server_completed_at?: string | null
          server_started_at?: string | null
          started_at?: string | null
          status?: string
          subject_id?: string | null
          updated_at?: string
          winner_user_id?: string | null
        }
        Update: {
          competition_code?: string
          competition_type?: string
          completed_at?: string | null
          configuration?: Json
          created_at?: string
          current_question_id?: string | null
          current_question_order?: number | null
          grade_level?: number
          id?: string
          question_count?: number
          scoring_rule_set_id?: string
          server_completed_at?: string | null
          server_started_at?: string | null
          started_at?: string | null
          status?: string
          subject_id?: string | null
          updated_at?: string
          winner_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "competitions_current_question_id_fkey"
            columns: ["current_question_id"]
            isOneToOne: false
            referencedRelation: "competition_questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competitions_scoring_rule_set_id_fkey"
            columns: ["scoring_rule_set_id"]
            isOneToOne: false
            referencedRelation: "scoring_rule_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competitions_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      copyright_reviews: {
        Row: {
          commercial_use_recommendation: string
          created_at: string
          evidence: Json
          id: string
          model_name: string | null
          notes: string | null
          originality_score: number | null
          prompt_version: string | null
          provider_name: string | null
          question_id: string | null
          review_type: string
          reviewed_by: string | null
          reviewer_type: string
          risk_level: string
          source_id: string | null
          staging_question_id: string | null
        }
        Insert: {
          commercial_use_recommendation?: string
          created_at?: string
          evidence?: Json
          id?: string
          model_name?: string | null
          notes?: string | null
          originality_score?: number | null
          prompt_version?: string | null
          provider_name?: string | null
          question_id?: string | null
          review_type: string
          reviewed_by?: string | null
          reviewer_type: string
          risk_level?: string
          source_id?: string | null
          staging_question_id?: string | null
        }
        Update: {
          commercial_use_recommendation?: string
          created_at?: string
          evidence?: Json
          id?: string
          model_name?: string | null
          notes?: string | null
          originality_score?: number | null
          prompt_version?: string | null
          provider_name?: string | null
          question_id?: string | null
          review_type?: string
          reviewed_by?: string | null
          reviewer_type?: string
          risk_level?: string
          source_id?: string | null
          staging_question_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "copyright_reviews_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "copyright_reviews_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "copyright_reviews_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "copyright_reviews_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "question_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "copyright_reviews_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      cosmetic_items: {
        Row: {
          asset_key: string | null
          compatible_character_code: string | null
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          item_code: string
          item_type: string
          metadata: Json
          name: string
          rarity: string
          unlock_type: string
          unlock_value: number | null
          updated_at: string
        }
        Insert: {
          asset_key?: string | null
          compatible_character_code?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          item_code: string
          item_type: string
          metadata?: Json
          name: string
          rarity?: string
          unlock_type?: string
          unlock_value?: number | null
          updated_at?: string
        }
        Update: {
          asset_key?: string | null
          compatible_character_code?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          item_code?: string
          item_type?: string
          metadata?: Json
          name?: string
          rarity?: string
          unlock_type?: string
          unlock_value?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      curriculum_aliases: {
        Row: {
          confidence_score: number | null
          created_at: string
          curriculum_version_id: string
          id: string
          legacy_taxonomy_id: string
          mapping_source: string
          notes: string | null
          relation_type: string
          review_status: string
          subtopic_id: string | null
          topic_id: string | null
          updated_at: string
        }
        Insert: {
          confidence_score?: number | null
          created_at?: string
          curriculum_version_id: string
          id?: string
          legacy_taxonomy_id: string
          mapping_source?: string
          notes?: string | null
          relation_type?: string
          review_status?: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Update: {
          confidence_score?: number | null
          created_at?: string
          curriculum_version_id?: string
          id?: string
          legacy_taxonomy_id?: string
          mapping_source?: string
          notes?: string | null
          relation_type?: string
          review_status?: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_aliases_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_aliases_legacy_taxonomy_id_fkey"
            columns: ["legacy_taxonomy_id"]
            isOneToOne: false
            referencedRelation: "legacy_taxonomy"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_aliases_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_aliases_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_outcome_aliases: {
        Row: {
          confidence: number | null
          created_at: string
          id: string
          mapping_source: string
          notes: string | null
          relation_type: string
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          source_outcome_id: string
          target_outcome_id: string
        }
        Insert: {
          confidence?: number | null
          created_at?: string
          id?: string
          mapping_source?: string
          notes?: string | null
          relation_type: string
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_outcome_id: string
          target_outcome_id: string
        }
        Update: {
          confidence?: number | null
          created_at?: string
          id?: string
          mapping_source?: string
          notes?: string | null
          relation_type?: string
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_outcome_id?: string
          target_outcome_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_outcome_aliases_source_outcome_id_fkey"
            columns: ["source_outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_outcome_aliases_target_outcome_id_fkey"
            columns: ["target_outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_outcomes: {
        Row: {
          created_at: string
          curriculum_version_id: string
          grade_level: number
          id: string
          is_active: boolean
          outcome_code: string | null
          outcome_text: string
          sort_order: number
          source_reference: string | null
          subject_id: string
          subtopic_id: string | null
          topic_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          curriculum_version_id: string
          grade_level: number
          id?: string
          is_active?: boolean
          outcome_code?: string | null
          outcome_text: string
          sort_order?: number
          source_reference?: string | null
          subject_id: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          curriculum_version_id?: string
          grade_level?: number
          id?: string
          is_active?: boolean
          outcome_code?: string | null
          outcome_text?: string
          sort_order?: number
          source_reference?: string | null
          subject_id?: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_outcomes_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_outcomes_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_outcomes_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_outcomes_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_prerequisites: {
        Row: {
          confidence: number | null
          created_at: string
          curriculum_version_id: string
          id: string
          notes: string | null
          prerequisite_grade_level: number | null
          prerequisite_subtopic_id: string | null
          prerequisite_topic_id: string | null
          requirement_level: string
          review_status: string
          source_type: string
          target_subtopic_id: string | null
          target_topic_id: string | null
          updated_at: string
        }
        Insert: {
          confidence?: number | null
          created_at?: string
          curriculum_version_id: string
          id?: string
          notes?: string | null
          prerequisite_grade_level?: number | null
          prerequisite_subtopic_id?: string | null
          prerequisite_topic_id?: string | null
          requirement_level?: string
          review_status?: string
          source_type?: string
          target_subtopic_id?: string | null
          target_topic_id?: string | null
          updated_at?: string
        }
        Update: {
          confidence?: number | null
          created_at?: string
          curriculum_version_id?: string
          id?: string
          notes?: string | null
          prerequisite_grade_level?: number | null
          prerequisite_subtopic_id?: string | null
          prerequisite_topic_id?: string | null
          requirement_level?: string
          review_status?: string
          source_type?: string
          target_subtopic_id?: string | null
          target_topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_prerequisites_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_prerequisites_prerequisite_subtopic_id_fkey"
            columns: ["prerequisite_subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_prerequisites_prerequisite_topic_id_fkey"
            columns: ["prerequisite_topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_prerequisites_target_subtopic_id_fkey"
            columns: ["target_subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_prerequisites_target_topic_id_fkey"
            columns: ["target_topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_schedule_items: {
        Row: {
          created_at: string
          end_week: number | null
          grade_level: number
          id: string
          is_active: boolean
          metadata: Json
          notes: string | null
          outcome_id: string | null
          schedule_profile_id: string
          start_week: number
          subject_id: string
          subtopic_id: string | null
          topic_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          end_week?: number | null
          grade_level: number
          id?: string
          is_active?: boolean
          metadata?: Json
          notes?: string | null
          outcome_id?: string | null
          schedule_profile_id: string
          start_week: number
          subject_id: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          end_week?: number | null
          grade_level?: number
          id?: string
          is_active?: boolean
          metadata?: Json
          notes?: string | null
          outcome_id?: string | null
          schedule_profile_id?: string
          start_week?: number
          subject_id?: string
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_schedule_items_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_schedule_items_schedule_profile_id_fkey"
            columns: ["schedule_profile_id"]
            isOneToOne: false
            referencedRelation: "curriculum_schedule_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_schedule_items_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_schedule_items_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_schedule_items_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_schedule_profiles: {
        Row: {
          code: string
          created_at: string
          curriculum_version_id: string
          description: string | null
          id: string
          is_active: boolean
          is_default: boolean
          metadata: Json
          name: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          curriculum_version_id: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          metadata?: Json
          name: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          curriculum_version_id?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          metadata?: Json
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_schedule_profiles_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_versions: {
        Row: {
          academic_year: string
          created_at: string
          framework: string
          id: string
          is_active: boolean
          is_default: boolean
          published_at: string | null
          source_name: string
          source_url: string | null
          updated_at: string
        }
        Insert: {
          academic_year: string
          created_at?: string
          framework: string
          id?: string
          is_active?: boolean
          is_default?: boolean
          published_at?: string | null
          source_name?: string
          source_url?: string | null
          updated_at?: string
        }
        Update: {
          academic_year?: string
          created_at?: string
          framework?: string
          id?: string
          is_active?: boolean
          is_default?: boolean
          published_at?: string | null
          source_name?: string
          source_url?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      excel_question_import_rows: {
        Row: {
          created_at: string
          id: string
          import_batch_id: string
          legacy_question_key: string | null
          legacy_taxonomy_id: string | null
          metadata: Json
          normalization_issues: Json
          normalization_status: string
          normalized_answer: string | null
          normalized_at: string | null
          normalized_cognitive_type: string | null
          normalized_difficulty: string | null
          normalized_exam_track: string | null
          normalized_grade_level: number | null
          normalized_is_new_generation: boolean | null
          normalized_primary_question_type: string | null
          normalized_quality_level: string | null
          normalized_question_number: number | null
          normalized_secondary_question_type: string | null
          normalized_subject_name: string | null
          normalized_test_code: string | null
          normalized_topic_code: string | null
          normalized_topic_name: string | null
          raw_answer: string | null
          raw_cognitive_type: string | null
          raw_data: Json
          raw_difficulty: string | null
          raw_exam_track: string | null
          raw_grade_level: string | null
          raw_link: string | null
          raw_new_generation: string | null
          raw_primary_question_type: string | null
          raw_quality_level: string | null
          raw_question_number: string | null
          raw_secondary_question_type: string | null
          raw_subject_name: string | null
          raw_test_code: string | null
          raw_topic_code: string | null
          raw_topic_name: string | null
          requires_ai_review: boolean
          requires_human_review: boolean
          source_row_number: number
          staged_at: string | null
          staging_question_id: string | null
          subject_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          import_batch_id: string
          legacy_question_key?: string | null
          legacy_taxonomy_id?: string | null
          metadata?: Json
          normalization_issues?: Json
          normalization_status?: string
          normalized_answer?: string | null
          normalized_at?: string | null
          normalized_cognitive_type?: string | null
          normalized_difficulty?: string | null
          normalized_exam_track?: string | null
          normalized_grade_level?: number | null
          normalized_is_new_generation?: boolean | null
          normalized_primary_question_type?: string | null
          normalized_quality_level?: string | null
          normalized_question_number?: number | null
          normalized_secondary_question_type?: string | null
          normalized_subject_name?: string | null
          normalized_test_code?: string | null
          normalized_topic_code?: string | null
          normalized_topic_name?: string | null
          raw_answer?: string | null
          raw_cognitive_type?: string | null
          raw_data?: Json
          raw_difficulty?: string | null
          raw_exam_track?: string | null
          raw_grade_level?: string | null
          raw_link?: string | null
          raw_new_generation?: string | null
          raw_primary_question_type?: string | null
          raw_quality_level?: string | null
          raw_question_number?: string | null
          raw_secondary_question_type?: string | null
          raw_subject_name?: string | null
          raw_test_code?: string | null
          raw_topic_code?: string | null
          raw_topic_name?: string | null
          requires_ai_review?: boolean
          requires_human_review?: boolean
          source_row_number: number
          staged_at?: string | null
          staging_question_id?: string | null
          subject_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          import_batch_id?: string
          legacy_question_key?: string | null
          legacy_taxonomy_id?: string | null
          metadata?: Json
          normalization_issues?: Json
          normalization_status?: string
          normalized_answer?: string | null
          normalized_at?: string | null
          normalized_cognitive_type?: string | null
          normalized_difficulty?: string | null
          normalized_exam_track?: string | null
          normalized_grade_level?: number | null
          normalized_is_new_generation?: boolean | null
          normalized_primary_question_type?: string | null
          normalized_quality_level?: string | null
          normalized_question_number?: number | null
          normalized_secondary_question_type?: string | null
          normalized_subject_name?: string | null
          normalized_test_code?: string | null
          normalized_topic_code?: string | null
          normalized_topic_name?: string | null
          raw_answer?: string | null
          raw_cognitive_type?: string | null
          raw_data?: Json
          raw_difficulty?: string | null
          raw_exam_track?: string | null
          raw_grade_level?: string | null
          raw_link?: string | null
          raw_new_generation?: string | null
          raw_primary_question_type?: string | null
          raw_quality_level?: string | null
          raw_question_number?: string | null
          raw_secondary_question_type?: string | null
          raw_subject_name?: string | null
          raw_test_code?: string | null
          raw_topic_code?: string | null
          raw_topic_name?: string | null
          requires_ai_review?: boolean
          requires_human_review?: boolean
          source_row_number?: number
          staged_at?: string | null
          staging_question_id?: string | null
          subject_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "excel_question_import_rows_import_batch_id_fkey"
            columns: ["import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "excel_question_import_rows_legacy_taxonomy_id_fkey"
            columns: ["legacy_taxonomy_id"]
            isOneToOne: false
            referencedRelation: "legacy_taxonomy"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "excel_question_import_rows_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "excel_question_import_rows_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      import_batches: {
        Row: {
          batch_type: string
          completed_at: string | null
          created_at: string
          error_items: number
          id: string
          processed_items: number
          source_id: string | null
          started_at: string | null
          status: string
          success_items: number
          total_items: number
          updated_at: string
        }
        Insert: {
          batch_type: string
          completed_at?: string | null
          created_at?: string
          error_items?: number
          id?: string
          processed_items?: number
          source_id?: string | null
          started_at?: string | null
          status?: string
          success_items?: number
          total_items?: number
          updated_at?: string
        }
        Update: {
          batch_type?: string
          completed_at?: string | null
          created_at?: string
          error_items?: number
          id?: string
          processed_items?: number
          source_id?: string | null
          started_at?: string | null
          status?: string
          success_items?: number
          total_items?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_batches_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "question_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      import_errors: {
        Row: {
          created_at: string
          error_code: string
          error_message: string
          id: string
          import_batch_id: string
          legacy_question_key: string | null
          raw_data: Json | null
          resolution_status: string
          resolved_at: string | null
          source_page_number: number | null
          source_row_number: number | null
        }
        Insert: {
          created_at?: string
          error_code: string
          error_message: string
          id?: string
          import_batch_id: string
          legacy_question_key?: string | null
          raw_data?: Json | null
          resolution_status?: string
          resolved_at?: string | null
          source_page_number?: number | null
          source_row_number?: number | null
        }
        Update: {
          created_at?: string
          error_code?: string
          error_message?: string
          id?: string
          import_batch_id?: string
          legacy_question_key?: string | null
          raw_data?: Json | null
          resolution_status?: string
          resolved_at?: string | null
          source_page_number?: number | null
          source_row_number?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "import_errors_import_batch_id_fkey"
            columns: ["import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      leaderboard_definitions: {
        Row: {
          configuration: Json
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          leaderboard_code: string
          name: string
          ranking_metric: string
          scope_type: string
          sort_direction: string
          updated_at: string
        }
        Insert: {
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          leaderboard_code: string
          name: string
          ranking_metric?: string
          scope_type: string
          sort_direction?: string
          updated_at?: string
        }
        Update: {
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          leaderboard_code?: string
          name?: string
          ranking_metric?: string
          scope_type?: string
          sort_direction?: string
          updated_at?: string
        }
        Relationships: []
      }
      leaderboard_entries: {
        Row: {
          grade_level: number | null
          id: string
          leaderboard_definition_id: string
          league_code: string | null
          metadata: Json
          metrics: Json
          points: number
          previous_rank_position: number | null
          rank_position: number | null
          scope_reference_id: string | null
          scope_type: string
          season_id: string
          subject_id: string | null
          subtopic_id: string | null
          topic_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          grade_level?: number | null
          id?: string
          leaderboard_definition_id: string
          league_code?: string | null
          metadata?: Json
          metrics?: Json
          points?: number
          previous_rank_position?: number | null
          rank_position?: number | null
          scope_reference_id?: string | null
          scope_type?: string
          season_id: string
          subject_id?: string | null
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          grade_level?: number | null
          id?: string
          leaderboard_definition_id?: string
          league_code?: string | null
          metadata?: Json
          metrics?: Json
          points?: number
          previous_rank_position?: number | null
          rank_position?: number | null
          scope_reference_id?: string | null
          scope_type?: string
          season_id?: string
          subject_id?: string | null
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "leaderboard_entries_leaderboard_definition_id_fkey"
            columns: ["leaderboard_definition_id"]
            isOneToOne: false
            referencedRelation: "leaderboard_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leaderboard_entries_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "leaderboard_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leaderboard_entries_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leaderboard_entries_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leaderboard_entries_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      leaderboard_seasons: {
        Row: {
          created_at: string
          ends_at: string
          id: string
          is_active: boolean
          metadata: Json
          name: string
          season_code: string
          season_type: string
          starts_at: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          ends_at: string
          id?: string
          is_active?: boolean
          metadata?: Json
          name: string
          season_code: string
          season_type?: string
          starts_at: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          ends_at?: string
          id?: string
          is_active?: boolean
          metadata?: Json
          name?: string
          season_code?: string
          season_type?: string
          starts_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      leaderboard_snapshots: {
        Row: {
          id: string
          leaderboard_entry_id: string
          metrics: Json
          points: number
          rank_position: number | null
          snapshot_at: string
        }
        Insert: {
          id?: string
          leaderboard_entry_id: string
          metrics?: Json
          points?: number
          rank_position?: number | null
          snapshot_at?: string
        }
        Update: {
          id?: string
          leaderboard_entry_id?: string
          metrics?: Json
          points?: number
          rank_position?: number | null
          snapshot_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leaderboard_snapshots_leaderboard_entry_id_fkey"
            columns: ["leaderboard_entry_id"]
            isOneToOne: false
            referencedRelation: "leaderboard_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      league_rewards: {
        Row: {
          condition_data: Json
          condition_type: string
          created_at: string
          id: string
          is_active: boolean
          league_id: string | null
          reward_code: string | null
          reward_data: Json
          reward_type: string
          reward_value: number | null
          season_id: string | null
        }
        Insert: {
          condition_data?: Json
          condition_type?: string
          created_at?: string
          id?: string
          is_active?: boolean
          league_id?: string | null
          reward_code?: string | null
          reward_data?: Json
          reward_type: string
          reward_value?: number | null
          season_id?: string | null
        }
        Update: {
          condition_data?: Json
          condition_type?: string
          created_at?: string
          id?: string
          is_active?: boolean
          league_id?: string | null
          reward_code?: string | null
          reward_data?: Json
          reward_type?: string
          reward_value?: number | null
          season_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "league_rewards_league_id_fkey"
            columns: ["league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "league_rewards_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "leaderboard_seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      league_rule_sets: {
        Row: {
          applies_to_scope: string
          configuration: Json
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          rule_set_code: string
          rule_type: string
          updated_at: string
        }
        Insert: {
          applies_to_scope?: string
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          rule_set_code: string
          rule_type?: string
          updated_at?: string
        }
        Update: {
          applies_to_scope?: string
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          rule_set_code?: string
          rule_type?: string
          updated_at?: string
        }
        Relationships: []
      }
      league_transition_rules: {
        Row: {
          configuration: Json
          created_at: string
          from_league_id: string | null
          id: string
          is_active: boolean
          max_percentile: number | null
          max_points: number | null
          max_rank: number | null
          min_percentile: number | null
          min_points: number | null
          min_rank: number | null
          rule_set_id: string | null
          to_league_id: string | null
          transition_type: string
        }
        Insert: {
          configuration?: Json
          created_at?: string
          from_league_id?: string | null
          id?: string
          is_active?: boolean
          max_percentile?: number | null
          max_points?: number | null
          max_rank?: number | null
          min_percentile?: number | null
          min_points?: number | null
          min_rank?: number | null
          rule_set_id?: string | null
          to_league_id?: string | null
          transition_type: string
        }
        Update: {
          configuration?: Json
          created_at?: string
          from_league_id?: string | null
          id?: string
          is_active?: boolean
          max_percentile?: number | null
          max_points?: number | null
          max_rank?: number | null
          min_percentile?: number | null
          min_points?: number | null
          min_rank?: number | null
          rule_set_id?: string | null
          to_league_id?: string | null
          transition_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "league_transition_rules_from_league_id_fkey"
            columns: ["from_league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "league_transition_rules_rule_set_id_fkey"
            columns: ["rule_set_id"]
            isOneToOne: false
            referencedRelation: "league_rule_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "league_transition_rules_to_league_id_fkey"
            columns: ["to_league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
        ]
      }
      leagues: {
        Row: {
          configuration: Json
          created_at: string
          description: string | null
          icon_key: string | null
          id: string
          is_active: boolean
          league_code: string
          league_type: string
          max_points: number | null
          min_points: number
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          configuration?: Json
          created_at?: string
          description?: string | null
          icon_key?: string | null
          id?: string
          is_active?: boolean
          league_code: string
          league_type?: string
          max_points?: number | null
          min_points?: number
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          configuration?: Json
          created_at?: string
          description?: string | null
          icon_key?: string | null
          id?: string
          is_active?: boolean
          league_code?: string
          league_type?: string
          max_points?: number | null
          min_points?: number
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      legacy_taxonomy: {
        Row: {
          created_at: string
          grade_level: number
          id: string
          is_active: boolean
          legacy_code: string | null
          source_name: string
          subject_name: string
          subtopic_name: string | null
          topic_name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          grade_level: number
          id?: string
          is_active?: boolean
          legacy_code?: string | null
          source_name?: string
          subject_name: string
          subtopic_name?: string | null
          topic_name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          grade_level?: number
          id?: string
          is_active?: boolean
          legacy_code?: string | null
          source_name?: string
          subject_name?: string
          subtopic_name?: string | null
          topic_name?: string
          updated_at?: string
        }
        Relationships: []
      }
      matchmaking_queue: {
        Row: {
          expires_at: string | null
          grade_level: number
          id: string
          joined_at: string
          league_id: string | null
          matched_at: string | null
          preferences: Json
          queue_type: string
          status: string
          subject_id: string | null
          user_id: string
        }
        Insert: {
          expires_at?: string | null
          grade_level: number
          id?: string
          joined_at?: string
          league_id?: string | null
          matched_at?: string | null
          preferences?: Json
          queue_type?: string
          status?: string
          subject_id?: string | null
          user_id: string
        }
        Update: {
          expires_at?: string | null
          grade_level?: number
          id?: string
          joined_at?: string
          league_id?: string | null
          matched_at?: string | null
          preferences?: Json
          queue_type?: string
          status?: string
          subject_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "matchmaking_queue_league_id_fkey"
            columns: ["league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matchmaking_queue_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      question_assets: {
        Row: {
          alt_text: string | null
          asset_type: string
          asset_url: string | null
          created_at: string
          id: string
          is_active: boolean
          question_id: string
          sort_order: number
          storage_path: string | null
          updated_at: string
          validation_status: string
        }
        Insert: {
          alt_text?: string | null
          asset_type: string
          asset_url?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          question_id: string
          sort_order?: number
          storage_path?: string | null
          updated_at?: string
          validation_status?: string
        }
        Update: {
          alt_text?: string | null
          asset_type?: string
          asset_url?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          question_id?: string
          sort_order?: number
          storage_path?: string | null
          updated_at?: string
          validation_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_assets_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_assets_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_assets_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      question_competition_usage_stats: {
        Row: {
          average_position: number | null
          calculated_at: string
          first_used_at: string | null
          last_used_at: string | null
          question_id: string
          total_competition_uses: number
          usage_metadata: Json
          uses_last_30_days: number
          uses_last_7_days: number
          uses_last_90_days: number
        }
        Insert: {
          average_position?: number | null
          calculated_at?: string
          first_used_at?: string | null
          last_used_at?: string | null
          question_id: string
          total_competition_uses?: number
          usage_metadata?: Json
          uses_last_30_days?: number
          uses_last_7_days?: number
          uses_last_90_days?: number
        }
        Update: {
          average_position?: number | null
          calculated_at?: string
          first_used_at?: string | null
          last_used_at?: string | null
          question_id?: string
          total_competition_uses?: number
          usage_metadata?: Json
          uses_last_30_days?: number
          uses_last_7_days?: number
          uses_last_90_days?: number
        }
        Relationships: [
          {
            foreignKeyName: "question_competition_usage_stats_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: true
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_competition_usage_stats_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: true
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_competition_usage_stats_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: true
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      question_curriculum_mappings: {
        Row: {
          confidence_score: number | null
          created_at: string
          curriculum_version_id: string
          id: string
          mapping_source: string
          question_id: string
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          subtopic_id: string | null
          topic_id: string
          updated_at: string
        }
        Insert: {
          confidence_score?: number | null
          created_at?: string
          curriculum_version_id: string
          id?: string
          mapping_source?: string
          question_id: string
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          subtopic_id?: string | null
          topic_id: string
          updated_at?: string
        }
        Update: {
          confidence_score?: number | null
          created_at?: string
          curriculum_version_id?: string
          id?: string
          mapping_source?: string
          question_id?: string
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          subtopic_id?: string | null
          topic_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_curriculum_mappings_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_curriculum_mappings_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_curriculum_mappings_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_curriculum_mappings_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_curriculum_mappings_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_curriculum_mappings_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      question_generation_requests: {
        Row: {
          ai_generation_spec: Json
          approved_at: string | null
          approved_by: string | null
          approved_question_count: number
          created_at: string
          current_question_count: number
          demand_snapshot_id: string | null
          generated_candidate_count: number
          generation_batch_size: number
          generation_completed_at: string | null
          generation_priority: string
          generation_started_at: string | null
          id: string
          metadata: Json
          placed_question_count: number
          rejected_at: string | null
          rejected_by: string | null
          rejected_question_count: number
          rejection_reason: string | null
          request_reason: Json
          request_status: string
          requested_question_count: number
          review_question_count: number
          updated_at: string
          vault_id: string
        }
        Insert: {
          ai_generation_spec?: Json
          approved_at?: string | null
          approved_by?: string | null
          approved_question_count?: number
          created_at?: string
          current_question_count?: number
          demand_snapshot_id?: string | null
          generated_candidate_count?: number
          generation_batch_size?: number
          generation_completed_at?: string | null
          generation_priority?: string
          generation_started_at?: string | null
          id?: string
          metadata?: Json
          placed_question_count?: number
          rejected_at?: string | null
          rejected_by?: string | null
          rejected_question_count?: number
          rejection_reason?: string | null
          request_reason?: Json
          request_status?: string
          requested_question_count: number
          review_question_count?: number
          updated_at?: string
          vault_id: string
        }
        Update: {
          ai_generation_spec?: Json
          approved_at?: string | null
          approved_by?: string | null
          approved_question_count?: number
          created_at?: string
          current_question_count?: number
          demand_snapshot_id?: string | null
          generated_candidate_count?: number
          generation_batch_size?: number
          generation_completed_at?: string | null
          generation_priority?: string
          generation_started_at?: string | null
          id?: string
          metadata?: Json
          placed_question_count?: number
          rejected_at?: string | null
          rejected_by?: string | null
          rejected_question_count?: number
          rejection_reason?: string | null
          request_reason?: Json
          request_status?: string
          requested_question_count?: number
          review_question_count?: number
          updated_at?: string
          vault_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_generation_requests_demand_snapshot_id_fkey"
            columns: ["demand_snapshot_id"]
            isOneToOne: false
            referencedRelation: "question_vault_demand_overview"
            referencedColumns: ["snapshot_id"]
          },
          {
            foreignKeyName: "question_generation_requests_demand_snapshot_id_fkey"
            columns: ["demand_snapshot_id"]
            isOneToOne: false
            referencedRelation: "question_vault_demand_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_generation_requests_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_generation_requests_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      question_generation_rules: {
        Row: {
          created_at: string
          curriculum_version_id: string | null
          grade_level: number | null
          id: string
          is_active: boolean
          metadata: Json
          rule_text: string
          rule_type: string
          severity: string
          source_type: string
          subject_id: string | null
          subtopic_id: string | null
          topic_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          curriculum_version_id?: string | null
          grade_level?: number | null
          id?: string
          is_active?: boolean
          metadata?: Json
          rule_text: string
          rule_type: string
          severity?: string
          source_type?: string
          subject_id?: string | null
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          curriculum_version_id?: string | null
          grade_level?: number | null
          id?: string
          is_active?: boolean
          metadata?: Json
          rule_text?: string
          rule_type?: string
          severity?: string
          source_type?: string
          subject_id?: string | null
          subtopic_id?: string | null
          topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_generation_rules_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_generation_rules_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_generation_rules_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_generation_rules_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      question_outcome_mappings: {
        Row: {
          confidence: number | null
          created_at: string
          id: string
          is_primary: boolean
          mapping_source: string
          outcome_id: string
          question_id: string
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          updated_at: string
        }
        Insert: {
          confidence?: number | null
          created_at?: string
          id?: string
          is_primary?: boolean
          mapping_source?: string
          outcome_id: string
          question_id: string
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          updated_at?: string
        }
        Update: {
          confidence?: number | null
          created_at?: string
          id?: string
          is_primary?: boolean
          mapping_source?: string
          outcome_id?: string
          question_id?: string
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_outcome_mappings_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_outcome_mappings_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_outcome_mappings_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_outcome_mappings_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      question_pool_gap_results: {
        Row: {
          analyzed_at: string
          analyzed_by_job_id: string | null
          current_count: number
          excess_count: number
          gap_status: string
          id: string
          missing_count: number
          target_count: number
          target_id: string
        }
        Insert: {
          analyzed_at?: string
          analyzed_by_job_id?: string | null
          current_count?: number
          excess_count?: number
          gap_status: string
          id?: string
          missing_count?: number
          target_count?: number
          target_id: string
        }
        Update: {
          analyzed_at?: string
          analyzed_by_job_id?: string | null
          current_count?: number
          excess_count?: number
          gap_status?: string
          id?: string
          missing_count?: number
          target_count?: number
          target_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_pool_gap_results_analyzed_by_job_id_fkey"
            columns: ["analyzed_by_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_pool_gap_results_target_id_fkey"
            columns: ["target_id"]
            isOneToOne: false
            referencedRelation: "question_pool_targets"
            referencedColumns: ["id"]
          },
        ]
      }
      question_pool_targets: {
        Row: {
          allow_ai_generation: boolean
          cognitive_type: string | null
          created_at: string
          curriculum_version_id: string
          difficulty: string | null
          grade_level: number
          id: string
          is_active: boolean
          maximum_count: number | null
          minimum_count: number
          notes: string | null
          outcome_id: string | null
          primary_question_type: string | null
          priority: string
          subject_id: string
          subtopic_id: string | null
          target_count: number
          topic_id: string | null
          updated_at: string
        }
        Insert: {
          allow_ai_generation?: boolean
          cognitive_type?: string | null
          created_at?: string
          curriculum_version_id: string
          difficulty?: string | null
          grade_level: number
          id?: string
          is_active?: boolean
          maximum_count?: number | null
          minimum_count?: number
          notes?: string | null
          outcome_id?: string | null
          primary_question_type?: string | null
          priority?: string
          subject_id: string
          subtopic_id?: string | null
          target_count?: number
          topic_id?: string | null
          updated_at?: string
        }
        Update: {
          allow_ai_generation?: boolean
          cognitive_type?: string | null
          created_at?: string
          curriculum_version_id?: string
          difficulty?: string | null
          grade_level?: number
          id?: string
          is_active?: boolean
          maximum_count?: number | null
          minimum_count?: number
          notes?: string | null
          outcome_id?: string | null
          primary_question_type?: string | null
          priority?: string
          subject_id?: string
          subtopic_id?: string | null
          target_count?: number
          topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_pool_targets_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_pool_targets_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_pool_targets_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_pool_targets_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_pool_targets_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      question_promotion_audit: {
        Row: {
          action: string
          created_at: string
          details: Json
          id: string
          performed_by: string | null
          promotion_request_id: string
          question_id: string | null
          staging_question_id: string
        }
        Insert: {
          action: string
          created_at?: string
          details?: Json
          id?: string
          performed_by?: string | null
          promotion_request_id: string
          question_id?: string | null
          staging_question_id: string
        }
        Update: {
          action?: string
          created_at?: string
          details?: Json
          id?: string
          performed_by?: string | null
          promotion_request_id?: string
          question_id?: string | null
          staging_question_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_promotion_audit_promotion_request_id_fkey"
            columns: ["promotion_request_id"]
            isOneToOne: false
            referencedRelation: "question_promotion_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_promotion_audit_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_promotion_audit_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_promotion_audit_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_promotion_audit_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      question_promotion_requests: {
        Row: {
          answer_checks_passed: boolean
          approved_at: string | null
          approved_by: string | null
          blocking_reason: string | null
          created_at: string
          deterministic_checks_passed: boolean
          grade_checks_passed: boolean
          human_approval_received: boolean
          human_approval_required: boolean
          id: string
          originality_checks_passed: boolean
          outcome_checks_passed: boolean
          prerequisite_checks_passed: boolean
          promoted_question_id: string | null
          quality_checks_passed: boolean
          similarity_checks_passed: boolean
          staging_question_id: string
          status: string
          topic_checks_passed: boolean
          updated_at: string
        }
        Insert: {
          answer_checks_passed?: boolean
          approved_at?: string | null
          approved_by?: string | null
          blocking_reason?: string | null
          created_at?: string
          deterministic_checks_passed?: boolean
          grade_checks_passed?: boolean
          human_approval_received?: boolean
          human_approval_required?: boolean
          id?: string
          originality_checks_passed?: boolean
          outcome_checks_passed?: boolean
          prerequisite_checks_passed?: boolean
          promoted_question_id?: string | null
          quality_checks_passed?: boolean
          similarity_checks_passed?: boolean
          staging_question_id: string
          status?: string
          topic_checks_passed?: boolean
          updated_at?: string
        }
        Update: {
          answer_checks_passed?: boolean
          approved_at?: string | null
          approved_by?: string | null
          blocking_reason?: string | null
          created_at?: string
          deterministic_checks_passed?: boolean
          grade_checks_passed?: boolean
          human_approval_received?: boolean
          human_approval_required?: boolean
          id?: string
          originality_checks_passed?: boolean
          outcome_checks_passed?: boolean
          prerequisite_checks_passed?: boolean
          promoted_question_id?: string | null
          quality_checks_passed?: boolean
          similarity_checks_passed?: boolean
          staging_question_id?: string
          status?: string
          topic_checks_passed?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_promotion_requests_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_promotion_requests_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_promotion_requests_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_promotion_requests_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      question_publication_events: {
        Row: {
          action: string
          checks_snapshot: Json
          id: string
          metadata: Json
          new_is_active: boolean
          performed_at: string
          performed_by: string
          previous_is_active: boolean
          question_id: string
          reason: string | null
          staging_question_id: string | null
        }
        Insert: {
          action: string
          checks_snapshot?: Json
          id?: string
          metadata?: Json
          new_is_active: boolean
          performed_at?: string
          performed_by: string
          previous_is_active: boolean
          question_id: string
          reason?: string | null
          staging_question_id?: string | null
        }
        Update: {
          action?: string
          checks_snapshot?: Json
          id?: string
          metadata?: Json
          new_is_active?: boolean
          performed_at?: string
          performed_by?: string
          previous_is_active?: boolean
          question_id?: string
          reason?: string | null
          staging_question_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "question_publication_events_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_publication_events_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_publication_events_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_publication_events_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      question_review_decisions: {
        Row: {
          created_at: string
          decision: string
          decision_source: string
          id: string
          notes: string | null
          reason_code: string | null
          reviewer_agent_id: string | null
          reviewer_user_id: string | null
          staging_question_id: string
        }
        Insert: {
          created_at?: string
          decision: string
          decision_source: string
          id?: string
          notes?: string | null
          reason_code?: string | null
          reviewer_agent_id?: string | null
          reviewer_user_id?: string | null
          staging_question_id: string
        }
        Update: {
          created_at?: string
          decision?: string
          decision_source?: string
          id?: string
          notes?: string | null
          reason_code?: string | null
          reviewer_agent_id?: string | null
          reviewer_user_id?: string | null
          staging_question_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_review_decisions_reviewer_agent_id_fkey"
            columns: ["reviewer_agent_id"]
            isOneToOne: false
            referencedRelation: "ai_agents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_review_decisions_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      question_scoring_time_bands: {
        Row: {
          band_code: string
          band_name: string
          configuration: Json
          created_at: string
          id: string
          is_active: boolean
          max_time_ms: number | null
          min_time_ms: number
          question_id: string
          scoring_rule_set_id: string
          solve_time_profile_id: string
          sort_order: number
        }
        Insert: {
          band_code: string
          band_name: string
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          max_time_ms?: number | null
          min_time_ms?: number
          question_id: string
          scoring_rule_set_id: string
          solve_time_profile_id: string
          sort_order?: number
        }
        Update: {
          band_code?: string
          band_name?: string
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          max_time_ms?: number | null
          min_time_ms?: number
          question_id?: string
          scoring_rule_set_id?: string
          solve_time_profile_id?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "question_scoring_time_bands_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_scoring_time_bands_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_scoring_time_bands_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_scoring_time_bands_scoring_rule_set_id_fkey"
            columns: ["scoring_rule_set_id"]
            isOneToOne: false
            referencedRelation: "scoring_rule_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_scoring_time_bands_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["solve_time_profile_id"]
          },
          {
            foreignKeyName: "question_scoring_time_bands_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      question_similarity_matches: {
        Row: {
          candidate_staging_id: string
          copyright_risk: boolean
          created_at: string
          details: Json
          id: string
          matched_question_id: string | null
          matched_staging_id: string | null
          review_status: string
          similarity_score: number
          similarity_type: string
        }
        Insert: {
          candidate_staging_id: string
          copyright_risk?: boolean
          created_at?: string
          details?: Json
          id?: string
          matched_question_id?: string | null
          matched_staging_id?: string | null
          review_status?: string
          similarity_score: number
          similarity_type: string
        }
        Update: {
          candidate_staging_id?: string
          copyright_risk?: boolean
          created_at?: string
          details?: Json
          id?: string
          matched_question_id?: string | null
          matched_staging_id?: string | null
          review_status?: string
          similarity_score?: number
          similarity_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_similarity_matches_candidate_staging_id_fkey"
            columns: ["candidate_staging_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_similarity_matches_matched_question_id_fkey"
            columns: ["matched_question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_similarity_matches_matched_question_id_fkey"
            columns: ["matched_question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_similarity_matches_matched_question_id_fkey"
            columns: ["matched_question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_similarity_matches_matched_staging_id_fkey"
            columns: ["matched_staging_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      question_solution_assets: {
        Row: {
          asset_text: string | null
          asset_type: string
          asset_url: string | null
          created_at: string
          id: string
          is_active: boolean
          question_id: string
          source_type: string
          updated_at: string
          validation_status: string
        }
        Insert: {
          asset_text?: string | null
          asset_type: string
          asset_url?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          question_id: string
          source_type?: string
          updated_at?: string
          validation_status?: string
        }
        Update: {
          asset_text?: string | null
          asset_type?: string
          asset_url?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          question_id?: string
          source_type?: string
          updated_at?: string
          validation_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_solution_assets_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solution_assets_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solution_assets_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      question_solve_time_calibrations: {
        Row: {
          absolute_difference_seconds: number | null
          ai_estimated_seconds: number
          calibration_data: Json
          calibration_decision: string
          created_at: string
          created_by_agent_id: string | null
          difference_percent: number | null
          id: string
          minimum_sample_required: number
          observed_median_seconds: number | null
          proposed_total_time_seconds: number | null
          question_id: string
          reason: string | null
          solve_time_profile_id: string
          statistics_id: string | null
        }
        Insert: {
          absolute_difference_seconds?: number | null
          ai_estimated_seconds: number
          calibration_data?: Json
          calibration_decision?: string
          created_at?: string
          created_by_agent_id?: string | null
          difference_percent?: number | null
          id?: string
          minimum_sample_required?: number
          observed_median_seconds?: number | null
          proposed_total_time_seconds?: number | null
          question_id: string
          reason?: string | null
          solve_time_profile_id: string
          statistics_id?: string | null
        }
        Update: {
          absolute_difference_seconds?: number | null
          ai_estimated_seconds?: number
          calibration_data?: Json
          calibration_decision?: string
          created_at?: string
          created_by_agent_id?: string | null
          difference_percent?: number | null
          id?: string
          minimum_sample_required?: number
          observed_median_seconds?: number | null
          proposed_total_time_seconds?: number | null
          question_id?: string
          reason?: string | null
          solve_time_profile_id?: string
          statistics_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "question_solve_time_calibrations_created_by_agent_id_fkey"
            columns: ["created_by_agent_id"]
            isOneToOne: false
            referencedRelation: "ai_agents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_solve_time_calibrations_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solve_time_calibrations_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solve_time_calibrations_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_solve_time_calibrations_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["solve_time_profile_id"]
          },
          {
            foreignKeyName: "question_solve_time_calibrations_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_solve_time_calibrations_statistics_id_fkey"
            columns: ["statistics_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_statistics"
            referencedColumns: ["id"]
          },
        ]
      }
      question_solve_time_profiles: {
        Row: {
          analysis_metadata: Json
          analysis_version: number
          calculation_load: string | null
          calculation_time_confidence: number | null
          calibration_status: string
          content_fingerprint: string | null
          created_at: string
          created_by_agent_id: string | null
          diagram_count: number
          estimated_calculation_step_count: number | null
          estimated_calculation_time_seconds: number
          estimated_other_time_seconds: number
          estimated_reading_time_seconds: number
          estimated_reasoning_step_count: number | null
          estimated_reasoning_time_seconds: number
          estimated_total_time_seconds: number | null
          estimated_visual_analysis_time_seconds: number
          formula_count: number
          graph_count: number
          id: string
          is_approved_for_scoring: boolean
          is_current: boolean
          option_word_count: number | null
          question_id: string
          reading_load: string | null
          reading_time_confidence: number | null
          reasoning_load: string | null
          reasoning_time_confidence: number | null
          recommended_time_limit_seconds: number | null
          required_formula_count: number | null
          review_status: string
          sentence_count: number | null
          table_count: number
          text_character_count: number | null
          text_word_count: number | null
          total_time_confidence: number | null
          updated_at: string
          visual_count: number
          visual_load: string | null
          visual_time_confidence: number | null
        }
        Insert: {
          analysis_metadata?: Json
          analysis_version?: number
          calculation_load?: string | null
          calculation_time_confidence?: number | null
          calibration_status?: string
          content_fingerprint?: string | null
          created_at?: string
          created_by_agent_id?: string | null
          diagram_count?: number
          estimated_calculation_step_count?: number | null
          estimated_calculation_time_seconds?: number
          estimated_other_time_seconds?: number
          estimated_reading_time_seconds?: number
          estimated_reasoning_step_count?: number | null
          estimated_reasoning_time_seconds?: number
          estimated_total_time_seconds?: number | null
          estimated_visual_analysis_time_seconds?: number
          formula_count?: number
          graph_count?: number
          id?: string
          is_approved_for_scoring?: boolean
          is_current?: boolean
          option_word_count?: number | null
          question_id: string
          reading_load?: string | null
          reading_time_confidence?: number | null
          reasoning_load?: string | null
          reasoning_time_confidence?: number | null
          recommended_time_limit_seconds?: number | null
          required_formula_count?: number | null
          review_status?: string
          sentence_count?: number | null
          table_count?: number
          text_character_count?: number | null
          text_word_count?: number | null
          total_time_confidence?: number | null
          updated_at?: string
          visual_count?: number
          visual_load?: string | null
          visual_time_confidence?: number | null
        }
        Update: {
          analysis_metadata?: Json
          analysis_version?: number
          calculation_load?: string | null
          calculation_time_confidence?: number | null
          calibration_status?: string
          content_fingerprint?: string | null
          created_at?: string
          created_by_agent_id?: string | null
          diagram_count?: number
          estimated_calculation_step_count?: number | null
          estimated_calculation_time_seconds?: number
          estimated_other_time_seconds?: number
          estimated_reading_time_seconds?: number
          estimated_reasoning_step_count?: number | null
          estimated_reasoning_time_seconds?: number
          estimated_total_time_seconds?: number | null
          estimated_visual_analysis_time_seconds?: number
          formula_count?: number
          graph_count?: number
          id?: string
          is_approved_for_scoring?: boolean
          is_current?: boolean
          option_word_count?: number | null
          question_id?: string
          reading_load?: string | null
          reading_time_confidence?: number | null
          reasoning_load?: string | null
          reasoning_time_confidence?: number | null
          recommended_time_limit_seconds?: number | null
          required_formula_count?: number | null
          review_status?: string
          sentence_count?: number | null
          table_count?: number
          text_character_count?: number | null
          text_word_count?: number | null
          total_time_confidence?: number | null
          updated_at?: string
          visual_count?: number
          visual_load?: string | null
          visual_time_confidence?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "question_solve_time_profiles_created_by_agent_id_fkey"
            columns: ["created_by_agent_id"]
            isOneToOne: false
            referencedRelation: "ai_agents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_solve_time_profiles_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solve_time_profiles_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solve_time_profiles_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      question_solve_time_reviews: {
        Row: {
          confidence_score: number | null
          created_at: string
          decision: string
          difference_percent: number | null
          id: string
          notes: string | null
          review_data: Json
          reviewed_calculation_time_seconds: number | null
          reviewed_reading_time_seconds: number | null
          reviewed_reasoning_time_seconds: number | null
          reviewed_total_time_seconds: number | null
          reviewed_visual_time_seconds: number | null
          reviewer_agent_id: string | null
          reviewer_type: string
          reviewer_user_id: string | null
          solve_time_profile_id: string
        }
        Insert: {
          confidence_score?: number | null
          created_at?: string
          decision: string
          difference_percent?: number | null
          id?: string
          notes?: string | null
          review_data?: Json
          reviewed_calculation_time_seconds?: number | null
          reviewed_reading_time_seconds?: number | null
          reviewed_reasoning_time_seconds?: number | null
          reviewed_total_time_seconds?: number | null
          reviewed_visual_time_seconds?: number | null
          reviewer_agent_id?: string | null
          reviewer_type: string
          reviewer_user_id?: string | null
          solve_time_profile_id: string
        }
        Update: {
          confidence_score?: number | null
          created_at?: string
          decision?: string
          difference_percent?: number | null
          id?: string
          notes?: string | null
          review_data?: Json
          reviewed_calculation_time_seconds?: number | null
          reviewed_reading_time_seconds?: number | null
          reviewed_reasoning_time_seconds?: number | null
          reviewed_total_time_seconds?: number | null
          reviewed_visual_time_seconds?: number | null
          reviewer_agent_id?: string | null
          reviewer_type?: string
          reviewer_user_id?: string | null
          solve_time_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_solve_time_reviews_reviewer_agent_id_fkey"
            columns: ["reviewer_agent_id"]
            isOneToOne: false
            referencedRelation: "ai_agents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_solve_time_reviews_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["solve_time_profile_id"]
          },
          {
            foreignKeyName: "question_solve_time_reviews_solve_time_profile_id_fkey"
            columns: ["solve_time_profile_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      question_solve_time_statistics: {
        Row: {
          average_time_seconds: number | null
          calculated_at: string
          cleaned_median_time_seconds: number | null
          cohort_key: string
          cohort_type: string
          correct_median_time_seconds: number | null
          correct_sample_size: number
          excluded_outlier_count: number
          id: string
          median_time_seconds: number | null
          p10_time_seconds: number | null
          p25_time_seconds: number | null
          p75_time_seconds: number | null
          p90_time_seconds: number | null
          pass_sample_size: number
          question_id: string
          sample_size: number
          statistical_data: Json
          wrong_median_time_seconds: number | null
          wrong_sample_size: number
        }
        Insert: {
          average_time_seconds?: number | null
          calculated_at?: string
          cleaned_median_time_seconds?: number | null
          cohort_key?: string
          cohort_type?: string
          correct_median_time_seconds?: number | null
          correct_sample_size?: number
          excluded_outlier_count?: number
          id?: string
          median_time_seconds?: number | null
          p10_time_seconds?: number | null
          p25_time_seconds?: number | null
          p75_time_seconds?: number | null
          p90_time_seconds?: number | null
          pass_sample_size?: number
          question_id: string
          sample_size?: number
          statistical_data?: Json
          wrong_median_time_seconds?: number | null
          wrong_sample_size?: number
        }
        Update: {
          average_time_seconds?: number | null
          calculated_at?: string
          cleaned_median_time_seconds?: number | null
          cohort_key?: string
          cohort_type?: string
          correct_median_time_seconds?: number | null
          correct_sample_size?: number
          excluded_outlier_count?: number
          id?: string
          median_time_seconds?: number | null
          p10_time_seconds?: number | null
          p25_time_seconds?: number | null
          p75_time_seconds?: number | null
          p90_time_seconds?: number | null
          pass_sample_size?: number
          question_id?: string
          sample_size?: number
          statistical_data?: Json
          wrong_median_time_seconds?: number | null
          wrong_sample_size?: number
        }
        Relationships: [
          {
            foreignKeyName: "question_solve_time_statistics_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solve_time_statistics_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_solve_time_statistics_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      question_source_locations: {
        Row: {
          created_at: string
          crop_reference: string | null
          extraction_confidence: number | null
          id: string
          page_number: number | null
          question_id: string
          question_number: number | null
          source_id: string
          source_question_code: string | null
          test_code: string | null
          test_number: number | null
        }
        Insert: {
          created_at?: string
          crop_reference?: string | null
          extraction_confidence?: number | null
          id?: string
          page_number?: number | null
          question_id: string
          question_number?: number | null
          source_id: string
          source_question_code?: string | null
          test_code?: string | null
          test_number?: number | null
        }
        Update: {
          created_at?: string
          crop_reference?: string | null
          extraction_confidence?: number | null
          id?: string
          page_number?: number | null
          question_id?: string
          question_number?: number | null
          source_id?: string
          source_question_code?: string | null
          test_code?: string | null
          test_number?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "question_source_locations_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_source_locations_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_source_locations_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_source_locations_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "question_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      question_sources: {
        Row: {
          author: string | null
          commercial_use_allowed: boolean
          created_at: string
          file_name: string | null
          id: string
          license_status: string
          notes: string | null
          ownership_status: string
          publication_year: number | null
          publisher: string | null
          source_reference: string | null
          source_type: string
          title: string
          updated_at: string
        }
        Insert: {
          author?: string | null
          commercial_use_allowed?: boolean
          created_at?: string
          file_name?: string | null
          id?: string
          license_status?: string
          notes?: string | null
          ownership_status?: string
          publication_year?: number | null
          publisher?: string | null
          source_reference?: string | null
          source_type: string
          title: string
          updated_at?: string
        }
        Update: {
          author?: string | null
          commercial_use_allowed?: boolean
          created_at?: string
          file_name?: string | null
          id?: string
          license_status?: string
          notes?: string | null
          ownership_status?: string
          publication_year?: number | null
          publisher?: string | null
          source_reference?: string | null
          source_type?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      question_vault_activation_windows: {
        Row: {
          created_at: string
          end_week: number | null
          ends_at: string | null
          id: string
          is_enabled: boolean
          metadata: Json
          priority: number
          start_week: number | null
          starts_at: string | null
          updated_at: string
          vault_id: string
          window_name: string | null
        }
        Insert: {
          created_at?: string
          end_week?: number | null
          ends_at?: string | null
          id?: string
          is_enabled?: boolean
          metadata?: Json
          priority?: number
          start_week?: number | null
          starts_at?: string | null
          updated_at?: string
          vault_id: string
          window_name?: string | null
        }
        Update: {
          created_at?: string
          end_week?: number | null
          ends_at?: string | null
          id?: string
          is_enabled?: boolean
          metadata?: Json
          priority?: number
          start_week?: number | null
          starts_at?: string | null
          updated_at?: string
          vault_id?: string
          window_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "question_vault_activation_windows_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vault_activation_windows_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      question_vault_demand_policies: {
        Row: {
          auto_create_generation_recommendation: boolean
          created_at: string
          current_content_ratio: number
          generation_batch_size: number
          high_shortage_threshold: number
          id: string
          inventory_scope: string
          is_active: boolean
          low_shortage_threshold: number
          metadata: Json
          minimum_inventory_floor: number
          review_content_ratio: number
          safety_factor: number
          target_repeat_weeks: number
          updated_at: string
          user_diversity_weight: number
          vault_id: string
          weekly_questions_per_student: number
        }
        Insert: {
          auto_create_generation_recommendation?: boolean
          created_at?: string
          current_content_ratio?: number
          generation_batch_size?: number
          high_shortage_threshold?: number
          id?: string
          inventory_scope?: string
          is_active?: boolean
          low_shortage_threshold?: number
          metadata?: Json
          minimum_inventory_floor?: number
          review_content_ratio?: number
          safety_factor?: number
          target_repeat_weeks?: number
          updated_at?: string
          user_diversity_weight?: number
          vault_id: string
          weekly_questions_per_student?: number
        }
        Update: {
          auto_create_generation_recommendation?: boolean
          created_at?: string
          current_content_ratio?: number
          generation_batch_size?: number
          high_shortage_threshold?: number
          id?: string
          inventory_scope?: string
          is_active?: boolean
          low_shortage_threshold?: number
          metadata?: Json
          minimum_inventory_floor?: number
          review_content_ratio?: number
          safety_factor?: number
          target_repeat_weeks?: number
          updated_at?: string
          user_diversity_weight?: number
          vault_id?: string
          weekly_questions_per_student?: number
        }
        Relationships: [
          {
            foreignKeyName: "question_vault_demand_policies_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: true
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vault_demand_policies_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: true
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      question_vault_demand_snapshots: {
        Row: {
          activation_target_count: number
          active_student_count: number
          actual_eligible_inventory: number
          calculated_dynamic_target: number
          calculation_details: Json
          created_at: string
          current_content_target: number
          diversity_multiplier: number
          estimated_weekly_attempts: number
          estimated_weeks_of_inventory: number | null
          excess_count: number
          final_target_inventory: number
          generation_priority: string
          generation_recommended: boolean
          id: string
          inventory_scope: string
          policy_id: string | null
          recommended_current_generation: number
          recommended_generation_count: number
          recommended_review_generation: number
          requested_week: number
          review_content_target: number
          safety_factor: number
          shortage_count: number
          target_repeat_weeks: number
          vault_id: string
          weekly_questions_per_student: number
        }
        Insert: {
          activation_target_count?: number
          active_student_count: number
          actual_eligible_inventory: number
          calculated_dynamic_target: number
          calculation_details?: Json
          created_at?: string
          current_content_target: number
          diversity_multiplier: number
          estimated_weekly_attempts: number
          estimated_weeks_of_inventory?: number | null
          excess_count: number
          final_target_inventory: number
          generation_priority: string
          generation_recommended: boolean
          id?: string
          inventory_scope: string
          policy_id?: string | null
          recommended_current_generation: number
          recommended_generation_count: number
          recommended_review_generation: number
          requested_week: number
          review_content_target: number
          safety_factor: number
          shortage_count: number
          target_repeat_weeks: number
          vault_id: string
          weekly_questions_per_student: number
        }
        Update: {
          activation_target_count?: number
          active_student_count?: number
          actual_eligible_inventory?: number
          calculated_dynamic_target?: number
          calculation_details?: Json
          created_at?: string
          current_content_target?: number
          diversity_multiplier?: number
          estimated_weekly_attempts?: number
          estimated_weeks_of_inventory?: number | null
          excess_count?: number
          final_target_inventory?: number
          generation_priority?: string
          generation_recommended?: boolean
          id?: string
          inventory_scope?: string
          policy_id?: string | null
          recommended_current_generation?: number
          recommended_generation_count?: number
          recommended_review_generation?: number
          requested_week?: number
          review_content_target?: number
          safety_factor?: number
          shortage_count?: number
          target_repeat_weeks?: number
          vault_id?: string
          weekly_questions_per_student?: number
        }
        Relationships: [
          {
            foreignKeyName: "question_vault_demand_snapshots_policy_id_fkey"
            columns: ["policy_id"]
            isOneToOne: false
            referencedRelation: "question_vault_demand_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_vault_demand_snapshots_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vault_demand_snapshots_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      question_vault_memberships: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          competition_eligible: boolean
          created_at: string
          eligibility_reason: Json
          exam_eligible: boolean
          id: string
          membership_source: string
          membership_status: string
          metadata: Json
          one_v_one_eligible: boolean
          practice_eligible: boolean
          question_id: string
          removed_at: string | null
          removed_by: string | null
          updated_at: string
          vault_id: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          competition_eligible?: boolean
          created_at?: string
          eligibility_reason?: Json
          exam_eligible?: boolean
          id?: string
          membership_source?: string
          membership_status?: string
          metadata?: Json
          one_v_one_eligible?: boolean
          practice_eligible?: boolean
          question_id: string
          removed_at?: string | null
          removed_by?: string | null
          updated_at?: string
          vault_id: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          competition_eligible?: boolean
          created_at?: string
          eligibility_reason?: Json
          exam_eligible?: boolean
          id?: string
          membership_source?: string
          membership_status?: string
          metadata?: Json
          one_v_one_eligible?: boolean
          practice_eligible?: boolean
          question_id?: string
          removed_at?: string | null
          removed_by?: string | null
          updated_at?: string
          vault_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_vault_memberships_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_vault_memberships_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "question_vault_memberships_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_vault_memberships_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vault_memberships_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      question_vault_rules: {
        Row: {
          created_at: string
          description: string | null
          field_name: string | null
          id: string
          is_active: boolean
          is_required: boolean
          operator: string | null
          priority: number
          rule_code: string
          rule_config: Json
          rule_type: string
          rule_value: Json | null
          updated_at: string
          vault_id: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          field_name?: string | null
          id?: string
          is_active?: boolean
          is_required?: boolean
          operator?: string | null
          priority?: number
          rule_code: string
          rule_config?: Json
          rule_type: string
          rule_value?: Json | null
          updated_at?: string
          vault_id: string
        }
        Update: {
          created_at?: string
          description?: string | null
          field_name?: string | null
          id?: string
          is_active?: boolean
          is_required?: boolean
          operator?: string | null
          priority?: number
          rule_code?: string
          rule_config?: Json
          rule_type?: string
          rule_value?: Json | null
          updated_at?: string
          vault_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_vault_rules_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vault_rules_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      question_vault_topics: {
        Row: {
          created_at: string
          id: string
          is_required: boolean
          legacy_topic_code: string | null
          legacy_topic_name: string | null
          metadata: Json
          topic_id: string | null
          topic_order: number | null
          vault_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_required?: boolean
          legacy_topic_code?: string | null
          legacy_topic_name?: string | null
          metadata?: Json
          topic_id?: string | null
          topic_order?: number | null
          vault_id: string
        }
        Update: {
          created_at?: string
          id?: string
          is_required?: boolean
          legacy_topic_code?: string | null
          legacy_topic_name?: string | null
          metadata?: Json
          topic_id?: string | null
          topic_order?: number | null
          vault_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_vault_topics_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vault_topics_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      question_vaults: {
        Row: {
          allow_competition: boolean
          allow_exam: boolean
          allow_one_v_one: boolean
          allow_practice: boolean
          created_at: string
          created_by: string | null
          description: string | null
          difficulty_level: string | null
          grade_level: number | null
          id: string
          is_active: boolean
          is_dynamic: boolean
          manual_question_assignment_allowed: boolean
          metadata: Json
          name: string
          parent_vault_id: string | null
          section_code: string | null
          section_order: number | null
          subject_id: string | null
          updated_at: string
          updated_by: string | null
          vault_code: string
          vault_type: string
        }
        Insert: {
          allow_competition?: boolean
          allow_exam?: boolean
          allow_one_v_one?: boolean
          allow_practice?: boolean
          created_at?: string
          created_by?: string | null
          description?: string | null
          difficulty_level?: string | null
          grade_level?: number | null
          id?: string
          is_active?: boolean
          is_dynamic?: boolean
          manual_question_assignment_allowed?: boolean
          metadata?: Json
          name: string
          parent_vault_id?: string | null
          section_code?: string | null
          section_order?: number | null
          subject_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vault_code: string
          vault_type?: string
        }
        Update: {
          allow_competition?: boolean
          allow_exam?: boolean
          allow_one_v_one?: boolean
          allow_practice?: boolean
          created_at?: string
          created_by?: string | null
          description?: string | null
          difficulty_level?: string | null
          grade_level?: number | null
          id?: string
          is_active?: boolean
          is_dynamic?: boolean
          manual_question_assignment_allowed?: boolean
          metadata?: Json
          name?: string
          parent_vault_id?: string | null
          section_code?: string | null
          section_order?: number | null
          subject_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vault_code?: string
          vault_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "question_vaults_parent_vault_id_fkey"
            columns: ["parent_vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vaults_parent_vault_id_fkey"
            columns: ["parent_vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_vaults_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      questions: {
        Row: {
          approval_status: string
          cognitive_type: string | null
          commercial_use_allowed: boolean
          correct_answer: string | null
          created_at: string
          difficulty: string | null
          estimated_solve_time_seconds: number | null
          exam_track: string | null
          grade_level: number
          has_visual: boolean
          id: string
          is_active: boolean
          is_new_generation: boolean
          legacy_question_key: string | null
          legacy_taxonomy_id: string | null
          license_status: string
          option_a: string | null
          option_b: string | null
          option_c: string | null
          option_d: string | null
          option_e: string | null
          ownership_status: string
          primary_question_type: string | null
          quality_level: string | null
          question_code: string
          question_text: string | null
          secondary_question_type: string | null
          subject_id: string
          updated_at: string
        }
        Insert: {
          approval_status?: string
          cognitive_type?: string | null
          commercial_use_allowed?: boolean
          correct_answer?: string | null
          created_at?: string
          difficulty?: string | null
          estimated_solve_time_seconds?: number | null
          exam_track?: string | null
          grade_level: number
          has_visual?: boolean
          id?: string
          is_active?: boolean
          is_new_generation?: boolean
          legacy_question_key?: string | null
          legacy_taxonomy_id?: string | null
          license_status?: string
          option_a?: string | null
          option_b?: string | null
          option_c?: string | null
          option_d?: string | null
          option_e?: string | null
          ownership_status?: string
          primary_question_type?: string | null
          quality_level?: string | null
          question_code: string
          question_text?: string | null
          secondary_question_type?: string | null
          subject_id: string
          updated_at?: string
        }
        Update: {
          approval_status?: string
          cognitive_type?: string | null
          commercial_use_allowed?: boolean
          correct_answer?: string | null
          created_at?: string
          difficulty?: string | null
          estimated_solve_time_seconds?: number | null
          exam_track?: string | null
          grade_level?: number
          has_visual?: boolean
          id?: string
          is_active?: boolean
          is_new_generation?: boolean
          legacy_question_key?: string | null
          legacy_taxonomy_id?: string | null
          license_status?: string
          option_a?: string | null
          option_b?: string | null
          option_c?: string | null
          option_d?: string | null
          option_e?: string | null
          ownership_status?: string
          primary_question_type?: string | null
          quality_level?: string | null
          question_code?: string
          question_text?: string | null
          secondary_question_type?: string | null
          subject_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "questions_legacy_taxonomy_id_fkey"
            columns: ["legacy_taxonomy_id"]
            isOneToOne: false
            referencedRelation: "legacy_taxonomy"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questions_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      review_queue: {
        Row: {
          assigned_at: string | null
          assigned_to: string | null
          created_at: string
          decision_notes: string | null
          entity_id: string
          entity_type: string
          id: string
          priority: string
          reason_code: string
          reason_details: Json
          resolved_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          assigned_at?: string | null
          assigned_to?: string | null
          created_at?: string
          decision_notes?: string | null
          entity_id: string
          entity_type: string
          id?: string
          priority?: string
          reason_code: string
          reason_details?: Json
          resolved_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_at?: string | null
          assigned_to?: string | null
          created_at?: string
          decision_notes?: string | null
          entity_id?: string
          entity_type?: string
          id?: string
          priority?: string
          reason_code?: string
          reason_details?: Json
          resolved_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      reward_definitions: {
        Row: {
          conditions: Json
          cooldown_seconds: number | null
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          is_repeatable: boolean
          name: string
          reward_code: string
          reward_data: Json
          reward_type: string
          reward_value: number | null
          trigger_type: string
          updated_at: string
        }
        Insert: {
          conditions?: Json
          cooldown_seconds?: number | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_repeatable?: boolean
          name: string
          reward_code: string
          reward_data?: Json
          reward_type: string
          reward_value?: number | null
          trigger_type: string
          updated_at?: string
        }
        Update: {
          conditions?: Json
          cooldown_seconds?: number | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_repeatable?: boolean
          name?: string
          reward_code?: string
          reward_data?: Json
          reward_type?: string
          reward_value?: number | null
          trigger_type?: string
          updated_at?: string
        }
        Relationships: []
      }
      reward_transactions: {
        Row: {
          amount: number | null
          created_at: string
          description: string | null
          id: string
          metadata: Json
          reward_type: string
          source_reference_id: string | null
          source_type: string
          user_id: string
        }
        Insert: {
          amount?: number | null
          created_at?: string
          description?: string | null
          id?: string
          metadata?: Json
          reward_type: string
          source_reference_id?: string | null
          source_type: string
          user_id: string
        }
        Update: {
          amount?: number | null
          created_at?: string
          description?: string | null
          id?: string
          metadata?: Json
          reward_type?: string
          source_reference_id?: string | null
          source_type?: string
          user_id?: string
        }
        Relationships: []
      }
      rpc_rate_limits: {
        Row: {
          hit_count: number
          rpc_name: string
          user_id: string
          window_start: string
        }
        Insert: {
          hit_count?: number
          rpc_name: string
          user_id: string
          window_start: string
        }
        Update: {
          hit_count?: number
          rpc_name?: string
          user_id?: string
          window_start?: string
        }
        Relationships: []
      }
      scoring_point_rules: {
        Row: {
          answer_result: string
          band_code: string | null
          configuration: Json
          created_at: string
          difficulty: string
          grade_level: number
          id: string
          is_active: boolean
          points: number
          rule_set_id: string
        }
        Insert: {
          answer_result: string
          band_code?: string | null
          configuration?: Json
          created_at?: string
          difficulty: string
          grade_level: number
          id?: string
          is_active?: boolean
          points?: number
          rule_set_id: string
        }
        Update: {
          answer_result?: string
          band_code?: string | null
          configuration?: Json
          created_at?: string
          difficulty?: string
          grade_level?: number
          id?: string
          is_active?: boolean
          points?: number
          rule_set_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "scoring_point_rules_rule_set_id_fkey"
            columns: ["rule_set_id"]
            isOneToOne: false
            referencedRelation: "scoring_rule_sets"
            referencedColumns: ["id"]
          },
        ]
      }
      scoring_rule_sets: {
        Row: {
          configuration: Json
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          rule_set_code: string
          updated_at: string
          version: string
        }
        Insert: {
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          rule_set_code: string
          updated_at?: string
          version: string
        }
        Update: {
          configuration?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          rule_set_code?: string
          updated_at?: string
          version?: string
        }
        Relationships: []
      }
      scoring_time_bands: {
        Row: {
          band_code: string
          band_name: string
          configuration: Json
          created_at: string
          difficulty: string
          grade_level: number
          id: string
          is_active: boolean
          max_time_ms: number | null
          min_time_ms: number | null
          rule_set_id: string
          sort_order: number
        }
        Insert: {
          band_code: string
          band_name: string
          configuration?: Json
          created_at?: string
          difficulty: string
          grade_level: number
          id?: string
          is_active?: boolean
          max_time_ms?: number | null
          min_time_ms?: number | null
          rule_set_id: string
          sort_order?: number
        }
        Update: {
          band_code?: string
          band_name?: string
          configuration?: Json
          created_at?: string
          difficulty?: string
          grade_level?: number
          id?: string
          is_active?: boolean
          max_time_ms?: number | null
          min_time_ms?: number | null
          rule_set_id?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "scoring_time_bands_rule_set_id_fkey"
            columns: ["rule_set_id"]
            isOneToOne: false
            referencedRelation: "scoring_rule_sets"
            referencedColumns: ["id"]
          },
        ]
      }
      staging_outcome_mappings: {
        Row: {
          confidence: number | null
          created_at: string
          id: string
          is_primary: boolean
          mapping_source: string
          outcome_id: string
          reasoning_summary: string | null
          review_status: string
          staging_question_id: string
          updated_at: string
        }
        Insert: {
          confidence?: number | null
          created_at?: string
          id?: string
          is_primary?: boolean
          mapping_source?: string
          outcome_id: string
          reasoning_summary?: string | null
          review_status?: string
          staging_question_id: string
          updated_at?: string
        }
        Update: {
          confidence?: number | null
          created_at?: string
          id?: string
          is_primary?: boolean
          mapping_source?: string
          outcome_id?: string
          reasoning_summary?: string | null
          review_status?: string
          staging_question_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "staging_outcome_mappings_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staging_outcome_mappings_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      staging_solve_time_profiles: {
        Row: {
          calculation_time_confidence: number | null
          created_at: string
          estimated_calculation_time_seconds: number
          estimated_other_time_seconds: number
          estimated_reading_time_seconds: number
          estimated_reasoning_time_seconds: number
          estimated_total_time_seconds: number | null
          estimated_visual_analysis_time_seconds: number
          feature_analysis: Json
          id: string
          metadata: Json
          reading_time_confidence: number | null
          reasoning_time_confidence: number | null
          recommended_time_limit_seconds: number | null
          review_status: string
          staging_question_id: string
          total_time_confidence: number | null
          updated_at: string
          visual_time_confidence: number | null
        }
        Insert: {
          calculation_time_confidence?: number | null
          created_at?: string
          estimated_calculation_time_seconds?: number
          estimated_other_time_seconds?: number
          estimated_reading_time_seconds?: number
          estimated_reasoning_time_seconds?: number
          estimated_total_time_seconds?: number | null
          estimated_visual_analysis_time_seconds?: number
          feature_analysis?: Json
          id?: string
          metadata?: Json
          reading_time_confidence?: number | null
          reasoning_time_confidence?: number | null
          recommended_time_limit_seconds?: number | null
          review_status?: string
          staging_question_id: string
          total_time_confidence?: number | null
          updated_at?: string
          visual_time_confidence?: number | null
        }
        Update: {
          calculation_time_confidence?: number | null
          created_at?: string
          estimated_calculation_time_seconds?: number
          estimated_other_time_seconds?: number
          estimated_reading_time_seconds?: number
          estimated_reasoning_time_seconds?: number
          estimated_total_time_seconds?: number | null
          estimated_visual_analysis_time_seconds?: number
          feature_analysis?: Json
          id?: string
          metadata?: Json
          reading_time_confidence?: number | null
          reasoning_time_confidence?: number | null
          recommended_time_limit_seconds?: number | null
          review_status?: string
          staging_question_id?: string
          total_time_confidence?: number | null
          updated_at?: string
          visual_time_confidence?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "staging_solve_time_profiles_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      student_characters: {
        Row: {
          character_id: string
          is_selected: boolean
          metadata: Json
          unlock_source: string | null
          unlocked_at: string
          user_id: string
        }
        Insert: {
          character_id: string
          is_selected?: boolean
          metadata?: Json
          unlock_source?: string | null
          unlocked_at?: string
          user_id: string
        }
        Update: {
          character_id?: string
          is_selected?: boolean
          metadata?: Json
          unlock_source?: string | null
          unlocked_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_characters_character_id_fkey"
            columns: ["character_id"]
            isOneToOne: false
            referencedRelation: "characters"
            referencedColumns: ["id"]
          },
        ]
      }
      student_cosmetics: {
        Row: {
          cosmetic_item_id: string
          is_equipped: boolean
          metadata: Json
          unlock_source: string | null
          unlocked_at: string
          user_id: string
        }
        Insert: {
          cosmetic_item_id: string
          is_equipped?: boolean
          metadata?: Json
          unlock_source?: string | null
          unlocked_at?: string
          user_id: string
        }
        Update: {
          cosmetic_item_id?: string
          is_equipped?: boolean
          metadata?: Json
          unlock_source?: string | null
          unlocked_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_cosmetics_cosmetic_item_id_fkey"
            columns: ["cosmetic_item_id"]
            isOneToOne: false
            referencedRelation: "cosmetic_items"
            referencedColumns: ["id"]
          },
        ]
      }
      student_dimension_metrics: {
        Row: {
          blank_count: number
          correct_count: number
          last_attempted_at: string | null
          metric_scope: string
          pass_timeout_count: number
          repeat_correct: number
          repeat_total: number
          scope_key: string
          total_attempts: number
          total_time_ms: number
          updated_at: string
          user_id: string
          wrong_count: number
        }
        Insert: {
          blank_count?: number
          correct_count?: number
          last_attempted_at?: string | null
          metric_scope: string
          pass_timeout_count?: number
          repeat_correct?: number
          repeat_total?: number
          scope_key: string
          total_attempts?: number
          total_time_ms?: number
          updated_at?: string
          user_id: string
          wrong_count?: number
        }
        Update: {
          blank_count?: number
          correct_count?: number
          last_attempted_at?: string | null
          metric_scope?: string
          pass_timeout_count?: number
          repeat_correct?: number
          repeat_total?: number
          scope_key?: string
          total_attempts?: number
          total_time_ms?: number
          updated_at?: string
          user_id?: string
          wrong_count?: number
        }
        Relationships: []
      }
      student_league_history: {
        Row: {
          created_at: string
          from_league_id: string | null
          id: string
          metadata: Json
          points_at_transition: number | null
          rank_at_transition: number | null
          reason: string | null
          season_id: string | null
          to_league_id: string | null
          transition_type: string
          user_id: string
        }
        Insert: {
          created_at?: string
          from_league_id?: string | null
          id?: string
          metadata?: Json
          points_at_transition?: number | null
          rank_at_transition?: number | null
          reason?: string | null
          season_id?: string | null
          to_league_id?: string | null
          transition_type: string
          user_id: string
        }
        Update: {
          created_at?: string
          from_league_id?: string | null
          id?: string
          metadata?: Json
          points_at_transition?: number | null
          rank_at_transition?: number | null
          reason?: string | null
          season_id?: string | null
          to_league_id?: string | null
          transition_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_league_history_from_league_id_fkey"
            columns: ["from_league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_league_history_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "leaderboard_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_league_history_to_league_id_fkey"
            columns: ["to_league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
        ]
      }
      student_league_memberships: {
        Row: {
          created_at: string
          current_points: number
          entered_at: string
          exited_at: string | null
          id: string
          is_current: boolean
          league_id: string
          membership_scope: string
          metadata: Json
          points_at_entry: number
          season_id: string | null
          subject_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          current_points?: number
          entered_at?: string
          exited_at?: string | null
          id?: string
          is_current?: boolean
          league_id: string
          membership_scope?: string
          metadata?: Json
          points_at_entry?: number
          season_id?: string | null
          subject_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          current_points?: number
          entered_at?: string
          exited_at?: string | null
          id?: string
          is_current?: boolean
          league_id?: string
          membership_scope?: string
          metadata?: Json
          points_at_entry?: number
          season_id?: string | null
          subject_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_league_memberships_league_id_fkey"
            columns: ["league_id"]
            isOneToOne: false
            referencedRelation: "leagues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_league_memberships_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "leaderboard_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_league_memberships_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      student_loadouts: {
        Row: {
          appearance_settings: Json
          character_id: string | null
          equipped_items: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          appearance_settings?: Json
          character_id?: string | null
          equipped_items?: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          appearance_settings?: Json
          character_id?: string | null
          equipped_items?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_loadouts_character_id_fkey"
            columns: ["character_id"]
            isOneToOne: false
            referencedRelation: "characters"
            referencedColumns: ["id"]
          },
        ]
      }
      student_pack_exposures: {
        Row: {
          attempt_context: string
          first_exposed_at: string
          fully_solved: boolean
          last_solved_at: string | null
          user_id: string
          vault_id: string
        }
        Insert: {
          attempt_context: string
          first_exposed_at?: string
          fully_solved?: boolean
          last_solved_at?: string | null
          user_id: string
          vault_id: string
        }
        Update: {
          attempt_context?: string
          first_exposed_at?: string
          fully_solved?: boolean
          last_solved_at?: string | null
          user_id?: string
          vault_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_pack_exposures_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "student_pack_exposures_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
        ]
      }
      student_profiles: {
        Row: {
          created_at: string
          grade_level: number
          id: string
          nickname: string
          schedule_profile_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          grade_level: number
          id: string
          nickname: string
          schedule_profile_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          grade_level?: number
          id?: string
          nickname?: string
          schedule_profile_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_profiles_schedule_profile_id_fkey"
            columns: ["schedule_profile_id"]
            isOneToOne: false
            referencedRelation: "curriculum_schedule_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      student_public_profiles: {
        Row: {
          avatar_key: string | null
          badges: Json
          character_key: string | null
          cosmetics: Json
          created_at: string
          grade_level: number
          is_visible: boolean
          league_code: string | null
          metadata: Json
          monthly_points: number
          nickname: string
          public_stats: Json
          total_points: number
          updated_at: string
          user_id: string
        }
        Insert: {
          avatar_key?: string | null
          badges?: Json
          character_key?: string | null
          cosmetics?: Json
          created_at?: string
          grade_level: number
          is_visible?: boolean
          league_code?: string | null
          metadata?: Json
          monthly_points?: number
          nickname: string
          public_stats?: Json
          total_points?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          avatar_key?: string | null
          badges?: Json
          character_key?: string | null
          cosmetics?: Json
          created_at?: string
          grade_level?: number
          is_visible?: boolean
          league_code?: string | null
          metadata?: Json
          monthly_points?: number
          nickname?: string
          public_stats?: Json
          total_points?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      student_question_attempts: {
        Row: {
          academic_year: string
          answered_at: string
          attempt_context: string
          attempt_number: number
          created_at: string
          id: string
          metadata: Json
          question_id: string
          result: string
          source_answer_id: string | null
          subject_id: string
          time_ms: number | null
          user_id: string
          week: number | null
        }
        Insert: {
          academic_year: string
          answered_at?: string
          attempt_context: string
          attempt_number: number
          created_at?: string
          id?: string
          metadata?: Json
          question_id: string
          result: string
          source_answer_id?: string | null
          subject_id: string
          time_ms?: number | null
          user_id: string
          week?: number | null
        }
        Update: {
          academic_year?: string
          answered_at?: string
          attempt_context?: string
          attempt_number?: number
          created_at?: string
          id?: string
          metadata?: Json
          question_id?: string
          result?: string
          source_answer_id?: string | null
          subject_id?: string
          time_ms?: number | null
          user_id?: string
          week?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "student_question_attempts_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "student_question_attempts_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "student_question_attempts_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_question_attempts_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      student_question_exposures: {
        Row: {
          attempt_context: string
          first_exposed_at: string
          question_id: string
          user_id: string
        }
        Insert: {
          attempt_context: string
          first_exposed_at?: string
          question_id: string
          user_id: string
        }
        Update: {
          attempt_context?: string
          first_exposed_at?: string
          question_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_question_exposures_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "student_question_exposures_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "student_question_exposures_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
        ]
      }
      student_training_levels: {
        Row: {
          attempt_count: number
          best_accuracy: number | null
          best_stars: number
          best_time_seconds: number | null
          completed_count: number
          first_completed_at: string | null
          last_played_at: string | null
          level_id: string
          metadata: Json
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          attempt_count?: number
          best_accuracy?: number | null
          best_stars?: number
          best_time_seconds?: number | null
          completed_count?: number
          first_completed_at?: string | null
          last_played_at?: string | null
          level_id: string
          metadata?: Json
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          attempt_count?: number
          best_accuracy?: number | null
          best_stars?: number
          best_time_seconds?: number | null
          completed_count?: number
          first_completed_at?: string | null
          last_played_at?: string | null
          level_id?: string
          metadata?: Json
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_training_levels_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
        ]
      }
      student_training_progress: {
        Row: {
          completed_levels: number
          created_at: string
          current_level_id: string | null
          metadata: Json
          progress_percent: number
          total_stars: number
          training_map_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          completed_levels?: number
          created_at?: string
          current_level_id?: string | null
          metadata?: Json
          progress_percent?: number
          total_stars?: number
          training_map_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          completed_levels?: number
          created_at?: string
          current_level_id?: string | null
          metadata?: Json
          progress_percent?: number
          total_stars?: number
          training_map_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_training_progress_current_level_id_fkey"
            columns: ["current_level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_training_progress_training_map_id_fkey"
            columns: ["training_map_id"]
            isOneToOne: false
            referencedRelation: "training_maps"
            referencedColumns: ["id"]
          },
        ]
      }
      student_visibility_settings: {
        Row: {
          additional_visibility: Json
          profile_visibility: string
          show_accuracy: boolean
          show_badges: boolean
          show_competition_count: boolean
          show_correct_count: boolean
          show_league: boolean
          show_points: boolean
          show_rank: boolean
          show_streak: boolean
          show_wins: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          additional_visibility?: Json
          profile_visibility?: string
          show_accuracy?: boolean
          show_badges?: boolean
          show_competition_count?: boolean
          show_correct_count?: boolean
          show_league?: boolean
          show_points?: boolean
          show_rank?: boolean
          show_streak?: boolean
          show_wins?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          additional_visibility?: Json
          profile_visibility?: string
          show_accuracy?: boolean
          show_badges?: boolean
          show_competition_count?: boolean
          show_correct_count?: boolean
          show_league?: boolean
          show_points?: boolean
          show_rank?: boolean
          show_streak?: boolean
          show_wins?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      student_wallets: {
        Row: {
          balances: Json
          points: number
          stars: number
          updated_at: string
          user_id: string
        }
        Insert: {
          balances?: Json
          points?: number
          stars?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          balances?: Json
          points?: number
          stars?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      student_weekly_counters: {
        Row: {
          academic_year: string
          new_questions_used: number
          subject_id: string
          updated_at: string
          user_id: string
          week: number
        }
        Insert: {
          academic_year: string
          new_questions_used?: number
          subject_id: string
          updated_at?: string
          user_id: string
          week: number
        }
        Update: {
          academic_year?: string
          new_questions_used?: number
          subject_id?: string
          updated_at?: string
          user_id?: string
          week?: number
        }
        Relationships: [
          {
            foreignKeyName: "student_weekly_counters_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      subjects: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          slug: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          slug: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          slug?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      subtopics: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          slug: string
          sort_order: number
          topic_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          slug: string
          sort_order?: number
          topic_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          slug?: string
          sort_order?: number
          topic_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subtopics_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      topics: {
        Row: {
          created_at: string
          curriculum_version_id: string
          grade_level: number
          id: string
          is_active: boolean
          name: string
          slug: string
          sort_order: number
          subject_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          curriculum_version_id: string
          grade_level: number
          id?: string
          is_active?: boolean
          name: string
          slug: string
          sort_order?: number
          subject_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          curriculum_version_id?: string
          grade_level?: number
          id?: string
          is_active?: boolean
          name?: string
          slug?: string
          sort_order?: number
          subject_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "topics_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "topics_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      training_attempts: {
        Row: {
          accuracy: number | null
          attempt_number: number
          completed: boolean
          completed_at: string | null
          correct_count: number
          id: string
          level_id: string
          pass_count: number
          points_earned: number
          question_count: number
          result_data: Json
          stars_earned: number
          started_at: string
          total_time_seconds: number | null
          user_id: string
          wrong_count: number
        }
        Insert: {
          accuracy?: number | null
          attempt_number: number
          completed?: boolean
          completed_at?: string | null
          correct_count?: number
          id?: string
          level_id: string
          pass_count?: number
          points_earned?: number
          question_count?: number
          result_data?: Json
          stars_earned?: number
          started_at?: string
          total_time_seconds?: number | null
          user_id: string
          wrong_count?: number
        }
        Update: {
          accuracy?: number | null
          attempt_number?: number
          completed?: boolean
          completed_at?: string | null
          correct_count?: number
          id?: string
          level_id?: string
          pass_count?: number
          points_earned?: number
          question_count?: number
          result_data?: Json
          stars_earned?: number
          started_at?: string
          total_time_seconds?: number | null
          user_id?: string
          wrong_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "training_attempts_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
        ]
      }
      training_level_connections: {
        Row: {
          configuration: Json
          connection_type: string
          created_at: string
          from_level_id: string
          id: string
          to_level_id: string
        }
        Insert: {
          configuration?: Json
          connection_type?: string
          created_at?: string
          from_level_id: string
          id?: string
          to_level_id: string
        }
        Update: {
          configuration?: Json
          connection_type?: string
          created_at?: string
          from_level_id?: string
          id?: string
          to_level_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "training_level_connections_from_level_id_fkey"
            columns: ["from_level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_level_connections_to_level_id_fkey"
            columns: ["to_level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
        ]
      }
      training_level_rewards: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          is_repeatable: boolean
          level_id: string
          reward_data: Json
          reward_type: string
          reward_value: number | null
          trigger_type: string
          trigger_value: number | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_repeatable?: boolean
          level_id: string
          reward_data?: Json
          reward_type: string
          reward_value?: number | null
          trigger_type?: string
          trigger_value?: number | null
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_repeatable?: boolean
          level_id?: string
          reward_data?: Json
          reward_type?: string
          reward_value?: number | null
          trigger_type?: string
          trigger_value?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "training_level_rewards_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
        ]
      }
      training_levels: {
        Row: {
          configuration: Json
          created_at: string
          description: string | null
          difficulty: string | null
          id: string
          is_active: boolean
          level_code: string
          level_type: string
          max_stars: number
          name: string
          outcome_id: string | null
          passing_accuracy: number
          question_count: number
          replay_allowed: boolean
          sort_order: number
          subtopic_id: string | null
          topic_id: string | null
          training_map_id: string
          updated_at: string
          visual_settings: Json
        }
        Insert: {
          configuration?: Json
          created_at?: string
          description?: string | null
          difficulty?: string | null
          id?: string
          is_active?: boolean
          level_code: string
          level_type?: string
          max_stars?: number
          name: string
          outcome_id?: string | null
          passing_accuracy?: number
          question_count?: number
          replay_allowed?: boolean
          sort_order?: number
          subtopic_id?: string | null
          topic_id?: string | null
          training_map_id: string
          updated_at?: string
          visual_settings?: Json
        }
        Update: {
          configuration?: Json
          created_at?: string
          description?: string | null
          difficulty?: string | null
          id?: string
          is_active?: boolean
          level_code?: string
          level_type?: string
          max_stars?: number
          name?: string
          outcome_id?: string | null
          passing_accuracy?: number
          question_count?: number
          replay_allowed?: boolean
          sort_order?: number
          subtopic_id?: string | null
          topic_id?: string | null
          training_map_id?: string
          updated_at?: string
          visual_settings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "training_levels_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_levels_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_levels_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_levels_training_map_id_fkey"
            columns: ["training_map_id"]
            isOneToOne: false
            referencedRelation: "training_maps"
            referencedColumns: ["id"]
          },
        ]
      }
      training_maps: {
        Row: {
          configuration: Json
          created_at: string
          curriculum_version_id: string | null
          description: string | null
          grade_level: number | null
          id: string
          is_active: boolean
          map_code: string
          map_type: string
          name: string
          subject_id: string | null
          updated_at: string
          visual_settings: Json
        }
        Insert: {
          configuration?: Json
          created_at?: string
          curriculum_version_id?: string | null
          description?: string | null
          grade_level?: number | null
          id?: string
          is_active?: boolean
          map_code: string
          map_type?: string
          name: string
          subject_id?: string | null
          updated_at?: string
          visual_settings?: Json
        }
        Update: {
          configuration?: Json
          created_at?: string
          curriculum_version_id?: string | null
          description?: string | null
          grade_level?: number | null
          id?: string
          is_active?: boolean
          map_code?: string
          map_type?: string
          name?: string
          subject_id?: string | null
          updated_at?: string
          visual_settings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "training_maps_curriculum_version_id_fkey"
            columns: ["curriculum_version_id"]
            isOneToOne: false
            referencedRelation: "curriculum_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_maps_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      training_star_rules: {
        Row: {
          configuration: Json
          created_at: string
          id: string
          is_active: boolean
          level_id: string | null
          maximum_time_seconds: number | null
          minimum_accuracy: number | null
          minimum_correct: number | null
          star_count: number
          training_map_id: string | null
        }
        Insert: {
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          level_id?: string | null
          maximum_time_seconds?: number | null
          minimum_accuracy?: number | null
          minimum_correct?: number | null
          star_count: number
          training_map_id?: string | null
        }
        Update: {
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          level_id?: string | null
          maximum_time_seconds?: number | null
          minimum_accuracy?: number | null
          minimum_correct?: number | null
          star_count?: number
          training_map_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "training_star_rules_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_star_rules_training_map_id_fkey"
            columns: ["training_map_id"]
            isOneToOne: false
            referencedRelation: "training_maps"
            referencedColumns: ["id"]
          },
        ]
      }
      training_unlock_rules: {
        Row: {
          configuration: Json
          created_at: string
          id: string
          is_active: boolean
          is_required: boolean
          level_id: string
          required_level_id: string | null
          required_value: number | null
          rule_type: string
        }
        Insert: {
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          is_required?: boolean
          level_id: string
          required_level_id?: string | null
          required_value?: number | null
          rule_type: string
        }
        Update: {
          configuration?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          is_required?: boolean
          level_id?: string
          required_level_id?: string | null
          required_value?: number | null
          rule_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "training_unlock_rules_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_unlock_rules_required_level_id_fkey"
            columns: ["required_level_id"]
            isOneToOne: false
            referencedRelation: "training_levels"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      ai_answer_verification_overview: {
        Row: {
          ai_job_id: string | null
          consensus_answer: string | null
          consensus_status: string | null
          created_at: string | null
          human_decision: string | null
          human_final_answer: string | null
          human_review_required: boolean | null
          minimum_confidence: number | null
          proposed_answer: string | null
          solver_1_answer: string | null
          solver_1_confidence: number | null
          solver_2_answer: string | null
          solver_2_confidence: number | null
          staging_question_id: string | null
          updated_at: string | null
          verification_run_id: string | null
        }
        Insert: {
          ai_job_id?: string | null
          consensus_answer?: string | null
          consensus_status?: string | null
          created_at?: string | null
          human_decision?: string | null
          human_final_answer?: string | null
          human_review_required?: boolean | null
          minimum_confidence?: number | null
          proposed_answer?: string | null
          solver_1_answer?: string | null
          solver_1_confidence?: number | null
          solver_2_answer?: string | null
          solver_2_confidence?: number | null
          staging_question_id?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Update: {
          ai_job_id?: string | null
          consensus_answer?: string | null
          consensus_status?: string | null
          created_at?: string | null
          human_decision?: string | null
          human_final_answer?: string | null
          human_review_required?: boolean | null
          minimum_confidence?: number | null
          proposed_answer?: string | null
          solver_1_answer?: string | null
          solver_1_confidence?: number | null
          solver_2_answer?: string | null
          solver_2_confidence?: number | null
          staging_question_id?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_answer_verification_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_answer_verification_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_curriculum_fit_overview: {
        Row: {
          created_at: string | null
          expected_grade_level: number | null
          expected_outcome_id: string | null
          expected_subject_id: string | null
          expected_subtopic_id: string | null
          expected_topic_id: string | null
          human_decision: string | null
          human_review_required: boolean | null
          minimum_confidence: number | null
          staging_question_id: string | null
          status: string | null
          updated_at: string | null
          verification_run_id: string | null
        }
        Insert: {
          created_at?: string | null
          expected_grade_level?: number | null
          expected_outcome_id?: string | null
          expected_subject_id?: string | null
          expected_subtopic_id?: string | null
          expected_topic_id?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          minimum_confidence?: number | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Update: {
          created_at?: string | null
          expected_grade_level?: number | null
          expected_outcome_id?: string | null
          expected_subject_id?: string | null
          expected_subtopic_id?: string | null
          expected_topic_id?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          minimum_confidence?: number | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_outcome_id_fkey"
            columns: ["expected_outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_subject_id_fkey"
            columns: ["expected_subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_subtopic_id_fkey"
            columns: ["expected_subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_expected_topic_id_fkey"
            columns: ["expected_topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_curriculum_fit_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_originality_verification_overview: {
        Row: {
          ai_job_id: string | null
          commercial_use_allowed: boolean | null
          consensus_originality_score: number | null
          copyright_risk_level: string | null
          created_at: string | null
          highest_detected_similarity_score: number | null
          highest_similarity_type: string | null
          human_decision: string | null
          human_review_required: boolean | null
          staging_question_id: string | null
          status: string | null
          updated_at: string | null
          verification_run_id: string | null
        }
        Insert: {
          ai_job_id?: string | null
          commercial_use_allowed?: never
          consensus_originality_score?: number | null
          copyright_risk_level?: string | null
          created_at?: string | null
          highest_detected_similarity_score?: number | null
          highest_similarity_type?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Update: {
          ai_job_id?: string | null
          commercial_use_allowed?: never
          consensus_originality_score?: number | null
          copyright_risk_level?: string | null
          created_at?: string | null
          highest_detected_similarity_score?: number | null
          highest_similarity_type?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_originality_verification_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_originality_verification_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_final_review_overview: {
        Row: {
          decision: string | null
          final_review_id: string | null
          promoted_question_id: string | null
          readiness_run_id: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          staging_question_id: string | null
        }
        Insert: {
          decision?: string | null
          final_review_id?: string | null
          promoted_question_id?: string | null
          readiness_run_id?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          staging_question_id?: string | null
        }
        Update: {
          decision?: string | null
          final_review_id?: string | null
          promoted_question_id?: string | null
          readiness_run_id?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          staging_question_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_final_reviews_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "question_publication_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "question_solve_time_overview"
            referencedColumns: ["question_id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_promoted_question_id_fkey"
            columns: ["promoted_question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_readiness_run_id_fkey"
            columns: ["readiness_run_id"]
            isOneToOne: false
            referencedRelation: "ai_question_readiness_overview"
            referencedColumns: ["readiness_run_id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_readiness_run_id_fkey"
            columns: ["readiness_run_id"]
            isOneToOne: false
            referencedRelation: "ai_question_readiness_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_final_reviews_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_quality_overview: {
        Row: {
          ai_job_id: string | null
          consensus_quality_score: number | null
          created_at: string | null
          human_decision: string | null
          human_review_required: boolean | null
          quality_run_id: string | null
          staging_question_id: string | null
          status: string | null
          updated_at: string | null
        }
        Insert: {
          ai_job_id?: string | null
          consensus_quality_score?: number | null
          created_at?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          quality_run_id?: string | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          ai_job_id?: string | null
          consensus_quality_score?: number | null
          created_at?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          quality_run_id?: string | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_quality_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_quality_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_question_readiness_overview: {
        Row: {
          ai_job_id: string | null
          answer_verification_passed: boolean | null
          blocking_reasons: Json | null
          commercial_ready: boolean | null
          curriculum_fit_passed: boolean | null
          evaluated_at: string | null
          originality_verification_passed: boolean | null
          question_quality_passed: boolean | null
          readiness_run_id: string | null
          readiness_score: number | null
          readiness_status: string | null
          solve_time_verification_passed: boolean | null
          staging_question_id: string | null
          updated_at: string | null
          warnings: Json | null
        }
        Insert: {
          ai_job_id?: string | null
          answer_verification_passed?: boolean | null
          blocking_reasons?: Json | null
          commercial_ready?: boolean | null
          curriculum_fit_passed?: boolean | null
          evaluated_at?: string | null
          originality_verification_passed?: boolean | null
          question_quality_passed?: boolean | null
          readiness_run_id?: string | null
          readiness_score?: number | null
          readiness_status?: string | null
          solve_time_verification_passed?: boolean | null
          staging_question_id?: string | null
          updated_at?: string | null
          warnings?: Json | null
        }
        Update: {
          ai_job_id?: string | null
          answer_verification_passed?: boolean | null
          blocking_reasons?: Json | null
          commercial_ready?: boolean | null
          curriculum_fit_passed?: boolean | null
          evaluated_at?: string | null
          originality_verification_passed?: boolean | null
          question_quality_passed?: boolean | null
          readiness_run_id?: string | null
          readiness_score?: number | null
          readiness_status?: string | null
          solve_time_verification_passed?: boolean | null
          staging_question_id?: string | null
          updated_at?: string | null
          warnings?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_question_readiness_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_question_readiness_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_solve_time_verification_overview: {
        Row: {
          ai_job_id: string | null
          consensus_calculation_seconds: number | null
          consensus_other_seconds: number | null
          consensus_reading_seconds: number | null
          consensus_reasoning_seconds: number | null
          consensus_total_seconds: number | null
          consensus_visual_seconds: number | null
          created_at: string | null
          human_decision: string | null
          human_review_required: boolean | null
          producer_difference_percent: number | null
          producer_estimated_total_seconds: number | null
          recommended_race_limit_seconds: number | null
          reviewer_difference_percent: number | null
          staging_question_id: string | null
          status: string | null
          updated_at: string | null
          verification_run_id: string | null
        }
        Insert: {
          ai_job_id?: string | null
          consensus_calculation_seconds?: number | null
          consensus_other_seconds?: number | null
          consensus_reading_seconds?: number | null
          consensus_reasoning_seconds?: number | null
          consensus_total_seconds?: number | null
          consensus_visual_seconds?: number | null
          created_at?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          producer_difference_percent?: number | null
          producer_estimated_total_seconds?: number | null
          recommended_race_limit_seconds?: number | null
          reviewer_difference_percent?: number | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Update: {
          ai_job_id?: string | null
          consensus_calculation_seconds?: number | null
          consensus_other_seconds?: number | null
          consensus_reading_seconds?: number | null
          consensus_reasoning_seconds?: number | null
          consensus_total_seconds?: number | null
          consensus_visual_seconds?: number | null
          created_at?: string | null
          human_decision?: string | null
          human_review_required?: boolean | null
          producer_difference_percent?: number | null
          producer_estimated_total_seconds?: number | null
          recommended_race_limit_seconds?: number | null
          reviewer_difference_percent?: number | null
          staging_question_id?: string | null
          status?: string | null
          updated_at?: string | null
          verification_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_solve_time_verification_runs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_solve_time_verification_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: true
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_teacher_review_overview: {
        Row: {
          correction_completed: boolean | null
          correction_proposal_count: number | null
          correction_required: boolean | null
          created_at: string | null
          current_stage: string | null
          error_hunter_passed: boolean | null
          final_checker_passed: boolean | null
          human_decision: string | null
          human_review_reason: string | null
          human_review_required: boolean | null
          issue_count: number | null
          overall_confidence: number | null
          overall_risk_level: string | null
          review_count: number | null
          review_run_id: string | null
          reviewer_disagreement_detected: boolean | null
          serious_issue_count: number | null
          staging_question_id: string | null
          status: string | null
          subject_id: string | null
          subject_teacher_passed: boolean | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_teacher_review_runs_staging_question_id_fkey"
            columns: ["staging_question_id"]
            isOneToOne: false
            referencedRelation: "ai_question_staging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_teacher_review_runs_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_worker_output_overview: {
        Row: {
          ai_job_id: string | null
          competition_factory_dispatch_id: string | null
          competition_generation_request_id: string | null
          duplicate_question_count: number | null
          generation_spec_id: string | null
          ingested_at: string | null
          inserted_question_count: number | null
          invalid_question_count: number | null
          model_name: string | null
          prompt_version: string | null
          provider_name: string | null
          received_at: string | null
          received_question_count: number | null
          remaining_question_count: number | null
          requested_question_count: number | null
          retry_required: boolean | null
          status: string | null
          valid_question_count: number | null
          validated_at: string | null
          worker_output_id: string | null
          worker_version: string | null
        }
        Insert: {
          ai_job_id?: string | null
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          duplicate_question_count?: number | null
          generation_spec_id?: string | null
          ingested_at?: string | null
          inserted_question_count?: number | null
          invalid_question_count?: number | null
          model_name?: string | null
          prompt_version?: string | null
          provider_name?: string | null
          received_at?: string | null
          received_question_count?: number | null
          remaining_question_count?: number | null
          requested_question_count?: number | null
          retry_required?: boolean | null
          status?: string | null
          valid_question_count?: number | null
          validated_at?: string | null
          worker_output_id?: string | null
          worker_version?: string | null
        }
        Update: {
          ai_job_id?: string | null
          competition_factory_dispatch_id?: string | null
          competition_generation_request_id?: string | null
          duplicate_question_count?: number | null
          generation_spec_id?: string | null
          ingested_at?: string | null
          inserted_question_count?: number | null
          invalid_question_count?: number | null
          model_name?: string | null
          prompt_version?: string | null
          provider_name?: string | null
          received_at?: string | null
          received_question_count?: number | null
          remaining_question_count?: number | null
          requested_question_count?: number | null
          retry_required?: boolean | null
          status?: string | null
          valid_question_count?: number | null
          validated_at?: string | null
          worker_output_id?: string | null
          worker_version?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_worker_outputs_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_dispatches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_factory_dispatch_id_fkey"
            columns: ["competition_factory_dispatch_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["dispatch_id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_factory_overview"
            referencedColumns: ["request_id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_competition_generation_request_id_fkey"
            columns: ["competition_generation_request_id"]
            isOneToOne: false
            referencedRelation: "competition_ai_generation_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_worker_outputs_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_ai_factory_overview: {
        Row: {
          ai_job_id: string | null
          approved_at: string | null
          approved_by: string | null
          approved_count: number | null
          copyright_blocked_count: number | null
          created_at: string | null
          curriculum_rejected_count: number | null
          dispatch_code: string | null
          dispatch_id: string | null
          generated_count: number | null
          generation_spec_id: string | null
          grade_level: number | null
          human_approved: boolean | null
          outcome_id: string | null
          profile_code: string | null
          profile_name: string | null
          rejected_count: number | null
          request_code: string | null
          request_id: string | null
          requested_question_count: number | null
          solve_time_rejected_count: number | null
          staging_count: number | null
          status: string | null
          subject_id: string | null
          subtopic_id: string | null
          topic_id: string | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "competition_ai_factory_dispatches_ai_job_id_fkey"
            columns: ["ai_job_id"]
            isOneToOne: false
            referencedRelation: "ai_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_ai_factory_dispatches_generation_spec_id_fkey"
            columns: ["generation_spec_id"]
            isOneToOne: false
            referencedRelation: "ai_generation_specs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      competition_pool_gap_overview: {
        Row: {
          analysis_run_id: string | null
          approved_active_questions: number | null
          buffer_target_count: number | null
          calculated_at: string | null
          cognitive_level: string | null
          difficulty: string | null
          gap_item_id: string | null
          gap_status: string | null
          grade_level: number | null
          max_solve_time_seconds: number | null
          min_solve_time_seconds: number | null
          missing_question_count: number | null
          outcome_id: string | null
          overused_questions: number | null
          profile_code: string | null
          profile_id: string | null
          profile_name: string | null
          question_type: string | null
          questions_with_time_profile: number | null
          scoring_ready_questions: number | null
          subject_id: string | null
          subtopic_id: string | null
          target_question_count: number | null
          topic_id: string | null
          total_matching_questions: number | null
          urgency_score: number | null
          usable_question_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "competition_pool_gap_items_analysis_run_id_fkey"
            columns: ["analysis_run_id"]
            isOneToOne: false
            referencedRelation: "competition_pool_analysis_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "curriculum_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_subtopic_id_fkey"
            columns: ["subtopic_id"]
            isOneToOne: false
            referencedRelation: "subtopics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "competition_pool_profiles_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "topics"
            referencedColumns: ["id"]
          },
        ]
      }
      question_publication_overview: {
        Row: {
          approval_status: string | null
          commercial_use_allowed: boolean | null
          grade_level: number | null
          is_active: boolean | null
          license_status: string | null
          ownership_status: string | null
          question_code: string | null
          question_id: string | null
          student_visible: boolean | null
          subject_id: string | null
          updated_at: string | null
        }
        Insert: {
          approval_status?: string | null
          commercial_use_allowed?: boolean | null
          grade_level?: number | null
          is_active?: boolean | null
          license_status?: string | null
          ownership_status?: string | null
          question_code?: string | null
          question_id?: string | null
          student_visible?: never
          subject_id?: string | null
          updated_at?: string | null
        }
        Update: {
          approval_status?: string | null
          commercial_use_allowed?: boolean | null
          grade_level?: number | null
          is_active?: boolean | null
          license_status?: string | null
          ownership_status?: string | null
          question_code?: string | null
          question_id?: string | null
          student_visible?: never
          subject_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "questions_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      question_solve_time_overview: {
        Row: {
          analysis_version: number | null
          calibration_status: string | null
          cleaned_median_time_seconds: number | null
          correct_median_time_seconds: number | null
          estimated_calculation_time_seconds: number | null
          estimated_other_time_seconds: number | null
          estimated_reading_time_seconds: number | null
          estimated_reasoning_time_seconds: number | null
          estimated_total_time_seconds: number | null
          estimated_visual_analysis_time_seconds: number | null
          is_approved_for_scoring: boolean | null
          median_time_seconds: number | null
          observed_difference_percent: number | null
          question_code: string | null
          question_id: string | null
          recommended_time_limit_seconds: number | null
          review_status: string | null
          sample_size: number | null
          solve_time_profile_id: string | null
          total_time_confidence: number | null
        }
        Relationships: []
      }
      question_vault_demand_overview: {
        Row: {
          activation_target_count: number | null
          active_student_count: number | null
          actual_eligible_inventory: number | null
          calculated_dynamic_target: number | null
          created_at: string | null
          current_content_target: number | null
          difficulty_level: string | null
          estimated_weekly_attempts: number | null
          excess_count: number | null
          final_target_inventory: number | null
          generation_priority: string | null
          generation_recommended: boolean | null
          grade_level: number | null
          inventory_scope: string | null
          recommended_current_generation: number | null
          recommended_generation_count: number | null
          recommended_review_generation: number | null
          requested_week: number | null
          review_content_target: number | null
          shortage_count: number | null
          snapshot_id: string | null
          subject_id: string | null
          vault_code: string | null
          vault_id: string | null
          vault_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "question_vault_demand_snapshots_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vault_inventory_overview"
            referencedColumns: ["vault_id"]
          },
          {
            foreignKeyName: "question_vault_demand_snapshots_vault_id_fkey"
            columns: ["vault_id"]
            isOneToOne: false
            referencedRelation: "question_vaults"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "question_vaults_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
      question_vault_inventory_overview: {
        Row: {
          actual_question_count: number | null
          competition_eligible_count: number | null
          difficulty_level: string | null
          grade_level: number | null
          one_v_one_eligible_count: number | null
          practice_eligible_count: number | null
          section_code: string | null
          subject_id: string | null
          target_question_count: number | null
          vault_code: string | null
          vault_id: string | null
          vault_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "question_vaults_subject_id_fkey"
            columns: ["subject_id"]
            isOneToOne: false
            referencedRelation: "subjects"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      _faz2_consume_weekly_capacity: {
        Args: {
          p_academic_year: string
          p_count: number
          p_subject_id: string
          p_user_id: string
          p_week: number
        }
        Returns: undefined
      }
      _faz2_lock_weekly_counter: {
        Args: {
          p_academic_year: string
          p_subject_id: string
          p_user_id: string
          p_week: number
        }
        Returns: number
      }
      _faz2_normalize_metric_key: { Args: { p_value: string }; Returns: string }
      _faz2_require_period: {
        Args: never
        Returns: {
          academic_year: string
          week: number
        }[]
      }
      _faz2_sanitize_question_payload: {
        Args: { p_question: Json }
        Returns: Json
      }
      _faz2_student_context: {
        Args: { p_user_id: string }
        Returns: {
          academic_year: string
          curriculum_version_id: string
          grade_level: number
          schedule_profile_id: string
        }[]
      }
      _faz4_consume_rate_limit: {
        Args: { p_limit: number; p_rpc_name: string; p_window_seconds: number }
        Returns: undefined
      }
      _faz5_apply_competition_points: {
        Args: { p_competition_id: string }
        Returns: undefined
      }
      academic_calendar_delete_week: {
        Args: { p_week: number; p_year: string }
        Returns: undefined
      }
      academic_calendar_has_permission: {
        Args: { p_permission_code: string }
        Returns: boolean
      }
      academic_calendar_list_weeks: {
        Args: { p_year: string }
        Returns: {
          academic_year: string
          ends_at: string
          is_started: boolean
          starts_at: string
          week: number
        }[]
      }
      academic_calendar_list_years: {
        Args: never
        Returns: {
          academic_year: string
          week_count: number
        }[]
      }
      academic_calendar_upsert_week: {
        Args: {
          p_ends_at: string
          p_starts_at: string
          p_week: number
          p_year: string
        }
        Returns: undefined
      }
      activate_question_for_students: {
        Args: { p_question_id: string; p_reason?: string }
        Returns: Json
      }
      admin_question_edit: {
        Args: {
          p_cognitive_type?: string
          p_correct_answer?: string
          p_difficulty?: string
          p_estimated_solve_time_seconds?: number
          p_has_visual?: boolean
          p_is_new_generation?: boolean
          p_option_a?: string
          p_option_b?: string
          p_option_c?: string
          p_option_d?: string
          p_option_e?: string
          p_primary_question_type?: string
          p_quality_level?: string
          p_question_id: string
          p_question_text?: string
          p_secondary_question_type?: string
        }
        Returns: Json
      }
      advance_competition_progress: {
        Args: { p_competition_id: string }
        Returns: Json
      }
      approve_competition_ai_generation_request: {
        Args: { p_request_id: string }
        Returns: string
      }
      approve_question_generation_request: {
        Args: { p_approved_by: string; p_request_id: string }
        Returns: Json
      }
      build_competition_ai_factory_job: {
        Args: { p_dispatch_id: string }
        Returns: Json
      }
      build_competition_generation_recommendation: {
        Args: { p_gap_item_id: string }
        Returns: Json
      }
      build_legacy_question_key: {
        Args: { p_question_number: number; p_test_code: string }
        Returns: string
      }
      calculate_accuracy: {
        Args: { p_answered: number; p_correct: number }
        Returns: number
      }
      calculate_competition_pool_gap_status: {
        Args: {
          p_buffer_percent: number
          p_minimum_safe_count: number
          p_target_count: number
          p_usable_count: number
        }
        Returns: Json
      }
      calculate_question_vault_demand: {
        Args: {
          p_active_student_count: number
          p_current_week: number
          p_vault_id: string
          p_weekly_questions_per_student?: number
        }
        Returns: Json
      }
      check_question_activation_readiness: {
        Args: { p_question_id: string }
        Returns: Json
      }
      claim_next_ai_generation_job: {
        Args: { p_lease_seconds?: number; p_worker_name: string }
        Returns: Json
      }
      create_missing_competition_timeouts: {
        Args: { p_competition_question_id: string }
        Returns: number
      }
      create_question_generation_request: {
        Args: { p_snapshot_id: string }
        Returns: string
      }
      current_user_has_admin_permission: {
        Args: { p_permission_code: string }
        Returns: boolean
      }
      deactivate_question_for_students: {
        Args: { p_question_id: string; p_reason: string }
        Returns: Json
      }
      decide_teacher_review: {
        Args: {
          p_correction_proposal_id?: string
          p_decision: string
          p_notes?: string
          p_review_run_id: string
        }
        Returns: Json
      }
      ensure_question_vault_demand_policy: {
        Args: { p_vault_id: string }
        Returns: string
      }
      equip_student_character: {
        Args: { p_character_id: string }
        Returns: Json
      }
      equip_student_cosmetic: {
        Args: { p_cosmetic_item_id: string; p_equip?: boolean }
        Returns: Json
      }
      evaluate_ai_question_readiness: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      fail_ai_job_claim: {
        Args: {
          p_ai_job_id: string
          p_claim_token: string
          p_error_code: string
          p_error_message: string
          p_retryable?: boolean
        }
        Returns: Json
      }
      finalize_competition_if_ready: {
        Args: { p_competition_id: string }
        Returns: undefined
      }
      get_ai_generation_retry_requirement: {
        Args: { p_ai_job_id: string }
        Returns: Json
      }
      get_ai_question_final_review_report: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      get_ai_question_readiness_report: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      get_ai_question_worker_contract: { Args: never; Returns: Json }
      get_ai_worker_output_report: {
        Args: { p_worker_output_id: string }
        Returns: Json
      }
      get_answer_verification_report: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      get_competition_ai_factory_job_status: {
        Args: { p_dispatch_id: string }
        Returns: Json
      }
      get_competition_question_payload: {
        Args: { p_competition_question_id: string }
        Returns: Json
      }
      get_competition_scoreboard: {
        Args: { p_competition_id: string }
        Returns: Json
      }
      get_current_competition_question: { Args: never; Returns: Json }
      get_curriculum_fit_report: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      get_excel_import_batch_summary: {
        Args: { p_import_batch_id: string }
        Returns: {
          ignored_rows: number
          import_batch_id: string
          needs_review_rows: number
          normalized_rows: number
          pending_rows: number
          quarantined_rows: number
          requires_ai_review_rows: number
          requires_human_review_rows: number
          staged_rows: number
          total_rows: number
        }[]
      }
      get_internal_correct_answer: {
        Args: { p_question_id: string }
        Returns: string
      }
      get_latest_competition_pool_report: { Args: never; Returns: Json }
      get_my_weekly_usage: { Args: never; Returns: Json }
      get_originality_verification_report: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      get_own_competition_result: {
        Args: { p_competition_id: string }
        Returns: Json
      }
      get_own_matchmaking_status: {
        Args: { p_subject_id: string }
        Returns: Json
      }
      get_question_base_eligibility: {
        Args: { p_question_id: string }
        Returns: {
          approval_status: string
          blocking_reasons: Json
          commercial_use_allowed: boolean
          competition_base_eligible: boolean
          has_answer: boolean
          is_active: boolean
          license_status: string
          one_v_one_base_eligible: boolean
          ownership_status: string
          practice_base_eligible: boolean
          question_id: string
        }[]
      }
      get_question_publication_report: {
        Args: { p_question_id: string }
        Returns: Json
      }
      get_question_quality_report: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      get_question_vault_inventory_summary: {
        Args: { p_vault_id: string }
        Returns: {
          actual_question_count: number
          competition_eligible_count: number
          exam_eligible_count: number
          excess_question_count: number
          missing_question_count: number
          one_v_one_eligible_count: number
          practice_eligible_count: number
          target_question_count: number
          vault_code: string
          vault_id: string
          vault_name: string
        }[]
      }
      get_solve_time_verification_report: {
        Args: { p_staging_question_id: string }
        Returns: Json
      }
      get_student_attempt_trend: {
        Args: { p_days: number }
        Returns: {
          avg_time_ms: number
          blank: number
          correct: number
          day: string
          pass_timeout: number
          success_rate: number
          total: number
          wrong: number
        }[]
      }
      get_student_dimension_summary: {
        Args: never
        Returns: {
          avg_time_ms: number
          blank: number
          correct: number
          display_name: string
          last_attempted_at: string
          pass_timeout: number
          repeat_correct: number
          repeat_success_rate: number
          repeat_total: number
          scope_key: string
          scope_type: string
          subject_id: string
          subject_name: string
          success_rate: number
          total: number
          total_time_ms: number
          wrong: number
        }[]
      }
      has_admin_permission: {
        Args: { p_permission_code: string; p_user_id: string }
        Returns: boolean
      }
      ingest_ai_worker_output: {
        Args: { p_worker_output_id: string }
        Returns: Json
      }
      ingest_student_attempt: {
        Args: {
          p_attempt_context: string
          p_metadata?: Json
          p_question_id: string
          p_result: string
          p_source_answer_id?: string
          p_time_ms?: number
        }
        Returns: Json
      }
      is_competition_participant: {
        Args: { p_competition_id: string; p_user_id?: string }
        Returns: boolean
      }
      is_current_user_admin: { Args: never; Returns: boolean }
      is_current_user_super_admin: { Args: never; Returns: boolean }
      join_matchmaking_queue: { Args: { p_subject_id: string }; Returns: Json }
      leave_matchmaking_queue: { Args: never; Returns: Json }
      list_training_outcomes: { Args: { p_subject_id: string }; Returns: Json }
      list_training_topics: { Args: { p_subject_id: string }; Returns: Json }
      normalize_excel_answer: { Args: { p_value: string }; Returns: string }
      normalize_excel_cognitive_type: {
        Args: { p_value: string }
        Returns: string
      }
      normalize_excel_difficulty: { Args: { p_value: string }; Returns: string }
      normalize_excel_exam_track: { Args: { p_value: string }; Returns: string }
      normalize_excel_grade_level: {
        Args: { p_value: string }
        Returns: number
      }
      normalize_excel_new_generation: {
        Args: { p_value: string }
        Returns: boolean
      }
      normalize_excel_positive_integer: {
        Args: { p_value: string }
        Returns: number
      }
      normalize_excel_quality: { Args: { p_value: string }; Returns: string }
      normalize_excel_question_import_batch: {
        Args: { p_batch_id: string; p_limit?: number }
        Returns: Json
      }
      normalize_excel_question_import_row: {
        Args: { p_row_id: string }
        Returns: Json
      }
      normalize_excel_secondary_question_type: {
        Args: { p_value: string }
        Returns: string
      }
      prepare_competition_pack: {
        Args: { p_competition_id: string }
        Returns: Json
      }
      recalculate_competition_player_score: {
        Args: { p_competition_id: string; p_user_id: string }
        Returns: undefined
      }
      register_ai_worker_output: {
        Args: {
          p_ai_job_id: string
          p_model_name?: string
          p_prompt_version?: string
          p_provider_name?: string
          p_raw_output: Json
          p_worker_version?: string
        }
        Returns: string
      }
      reject_question_generation_request: {
        Args: { p_reason: string; p_rejected_by: string; p_request_id: string }
        Returns: Json
      }
      release_competition_question: {
        Args: { p_competition_id: string; p_question_order: number }
        Returns: string
      }
      renew_ai_job_lease: {
        Args: {
          p_ai_job_id: string
          p_claim_token: string
          p_lease_seconds?: number
        }
        Returns: Json
      }
      resolve_competition_points: {
        Args: {
          p_answer_result: string
          p_band_code: string
          p_difficulty: string
          p_grade_level: number
          p_rule_set_id: string
        }
        Returns: number
      }
      resolve_competition_question_time_limit: {
        Args: { p_competition_question_id: string }
        Returns: Json
      }
      resolve_competition_time_band: {
        Args: {
          p_difficulty: string
          p_grade_level: number
          p_question_id: string
          p_rule_set_id: string
          p_time_ms: number
        }
        Returns: string
      }
      resolve_current_academic_period: {
        Args: never
        Returns: {
          academic_year: string
          week: number
        }[]
      }
      review_and_promote_ai_question: {
        Args: {
          p_decision: string
          p_review_notes?: string
          p_staging_question_id: string
        }
        Returns: Json
      }
      review_answer_verification: {
        Args: {
          p_decision: string
          p_final_answer?: string
          p_verification_run_id: string
        }
        Returns: Json
      }
      review_curriculum_fit: {
        Args: { p_decision: string; p_verification_run_id: string }
        Returns: Json
      }
      review_originality_verification: {
        Args: { p_decision: string; p_verification_run_id: string }
        Returns: Json
      }
      review_question_quality: {
        Args: { p_decision: string; p_quality_run_id: string }
        Returns: Json
      }
      review_solve_time_verification: {
        Args: {
          p_decision: string
          p_race_limit_seconds?: number
          p_total_seconds?: number
          p_verification_run_id: string
        }
        Returns: Json
      }
      run_competition_pool_analysis: {
        Args: {
          p_grade_level?: number
          p_profile_id?: string
          p_run_type?: string
          p_subject_id?: string
        }
        Returns: string
      }
      select_training_questions: {
        Args: {
          p_limit?: number
          p_outcome_id?: string
          p_subject_id: string
          p_topic_id?: string
        }
        Returns: Json
      }
      set_competition_player_ready: {
        Args: { p_competition_id: string }
        Returns: Json
      }
      start_answer_verification: {
        Args: { p_minimum_confidence?: number; p_staging_question_id: string }
        Returns: string
      }
      start_curriculum_fit_verification: {
        Args: { p_minimum_confidence?: number; p_staging_question_id: string }
        Returns: string
      }
      start_originality_verification: {
        Args: {
          p_critical_similarity_score?: number
          p_maximum_similarity_score?: number
          p_minimum_confidence?: number
          p_minimum_originality_score?: number
          p_staging_question_id: string
        }
        Returns: string
      }
      start_question_quality_review: {
        Args: {
          p_minimum_confidence?: number
          p_minimum_quality_score?: number
          p_staging_question_id: string
        }
        Returns: string
      }
      start_solve_time_verification: {
        Args: {
          p_max_producer_difference_percent?: number
          p_max_reviewer_difference_percent?: number
          p_minimum_confidence?: number
          p_staging_question_id: string
        }
        Returns: string
      }
      submit_answer_solver_result: {
        Args: {
          p_answer: string
          p_confidence: number
          p_model_name?: string
          p_prompt_version?: string
          p_provider_name?: string
          p_reasoning_summary?: string
          p_result?: Json
          p_solver_number: number
          p_verification_run_id: string
        }
        Returns: Json
      }
      submit_competition_answer: {
        Args: { p_competition_question_id: string; p_submitted_answer?: string }
        Returns: Json
      }
      submit_curriculum_fit_review: {
        Args: {
          p_confidence_score?: number
          p_details?: Json
          p_grade_fit_score?: number
          p_model_name?: string
          p_outcome_fit_score?: number
          p_prerequisite_details?: Json
          p_prerequisite_violation?: boolean
          p_prompt_version?: string
          p_provider_name?: string
          p_required_prior_knowledge?: Json
          p_review_summary?: string
          p_reviewer_number: number
          p_subject_fit_score?: number
          p_subtopic_fit_score?: number
          p_suggested_grade_level: number
          p_suggested_outcome_id?: string
          p_suggested_subject_id: string
          p_suggested_subtopic_id?: string
          p_suggested_topic_id?: string
          p_topic_fit_score?: number
          p_verification_run_id: string
        }
        Returns: Json
      }
      submit_originality_review: {
        Args: {
          p_concept_similarity_score: number
          p_confidence_score?: number
          p_copyright_risk_level?: string
          p_evidence?: Json
          p_exact_similarity_score: number
          p_highest_similarity_type: string
          p_matched_question_id?: string
          p_matched_source_id?: string
          p_matched_staging_id?: string
          p_metadata?: Json
          p_model_name?: string
          p_originality_score: number
          p_prompt_version?: string
          p_provider_name?: string
          p_review_summary?: string
          p_reviewer_number: number
          p_semantic_similarity_score: number
          p_solution_path_copy_risk?: boolean
          p_solution_path_similarity_score: number
          p_structural_similarity_score: number
          p_superficial_rewrite_detected?: boolean
          p_template_copy_detected?: boolean
          p_text_similarity_score: number
          p_verification_run_id: string
        }
        Returns: Json
      }
      submit_question_quality_review: {
        Args: {
          p_age_grade_language_score: number
          p_age_inappropriate_language?: boolean
          p_ambiguous_wording?: boolean
          p_clarity_score: number
          p_cognitive_fit_score?: number
          p_confidence_score?: number
          p_difficulty_fit_score?: number
          p_factual_error_detected?: boolean
          p_grammar_problem_detected?: boolean
          p_language_score: number
          p_metadata?: Json
          p_misleading_option_risk?: boolean
          p_missing_information_detected?: boolean
          p_model_name?: string
          p_multiple_correct_answer_risk?: boolean
          p_no_correct_answer_risk?: boolean
          p_option_quality_score: number
          p_overall_quality_score: number
          p_problems?: Json
          p_prompt_version?: string
          p_provider_name?: string
          p_quality_run_id: string
          p_question_type_fit_score?: number
          p_review_summary?: string
          p_reviewer_number: number
          p_scientific_accuracy_score: number
          p_scientific_error_detected?: boolean
          p_suggested_cognitive_type?: string
          p_suggested_difficulty?: string
          p_suggested_primary_question_type?: string
          p_suggestions?: Json
          p_unnecessary_information_problem?: boolean
        }
        Returns: Json
      }
      submit_solve_time_review: {
        Args: {
          p_calculation_details?: Json
          p_calculation_load?: string
          p_calculation_seconds: number
          p_calculation_step_count?: number
          p_confidence_score: number
          p_diagram_count?: number
          p_formula_count?: number
          p_graph_count?: number
          p_metadata?: Json
          p_model_name?: string
          p_other_seconds: number
          p_prompt_version?: string
          p_provider_name?: string
          p_reading_load?: string
          p_reading_seconds: number
          p_reasoning_load?: string
          p_reasoning_seconds: number
          p_reasoning_step_count?: number
          p_recommended_race_limit_seconds: number
          p_review_summary?: string
          p_reviewer_number: number
          p_table_count?: number
          p_verification_run_id: string
          p_visual_analysis_seconds: number
          p_visual_count?: number
          p_visual_load?: string
        }
        Returns: Json
      }
      submit_training_attempt: {
        Args: {
          p_action?: string
          p_choice?: string
          p_client_key?: string
          p_question_id: string
          p_time_ms?: number
        }
        Returns: Json
      }
      sync_competition_state: {
        Args: { p_competition_id: string }
        Returns: Json
      }
      teacher_review_admin_has_permission: {
        Args: { p_permission_code: string }
        Returns: boolean
      }
      unequip_student_character: { Args: never; Returns: Json }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

