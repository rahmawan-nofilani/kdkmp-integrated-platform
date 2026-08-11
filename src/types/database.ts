export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  __InternalSupabase: {
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      audit_logs: {
        Row: {
          action_code: string
          actor_profile_id: string | null
          after_data: Json | null
          before_data: Json | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          id: string
          organization_id: string | null
          reason: string | null
          request_id: string | null
          session_id: string | null
          source_ip: unknown
          user_agent: string | null
        }
        Insert: {
          action_code: string
          actor_profile_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          organization_id?: string | null
          reason?: string | null
          request_id?: string | null
          session_id?: string | null
          source_ip?: unknown
          user_agent?: string | null
        }
        Update: {
          action_code?: string
          actor_profile_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          organization_id?: string | null
          reason?: string | null
          request_id?: string | null
          session_id?: string | null
          source_ip?: unknown
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_actor_profile_id_fkey"
            columns: ["actor_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      data_scopes: {
        Row: {
          created_at: string
          id: string
          name: string
          organization_id: string | null
          organization_node_id: string | null
          organization_unit_id: string | null
          scope_type: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          organization_id?: string | null
          organization_node_id?: string | null
          organization_unit_id?: string | null
          scope_type: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          organization_id?: string | null
          organization_node_id?: string | null
          organization_unit_id?: string | null
          scope_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "data_scopes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_scopes_organization_node_id_fkey"
            columns: ["organization_node_id"]
            isOneToOne: false
            referencedRelation: "organization_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_scopes_organization_unit_id_fkey"
            columns: ["organization_unit_id"]
            isOneToOne: false
            referencedRelation: "organization_units"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_modules: {
        Row: {
          created_at: string
          enabled: boolean
          id: string
          module_code: string
          organization_id: string
          organization_unit_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          enabled?: boolean
          id?: string
          module_code: string
          organization_id: string
          organization_unit_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          enabled?: boolean
          id?: string
          module_code?: string
          organization_id?: string
          organization_unit_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_modules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_modules_organization_unit_id_fkey"
            columns: ["organization_unit_id"]
            isOneToOne: false
            referencedRelation: "organization_units"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_nodes: {
        Row: {
          code: string
          created_at: string
          id: string
          name: string
          node_type: string
          organization_id: string
          parent_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          name: string
          node_type: string
          organization_id: string
          parent_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          name?: string
          node_type?: string
          organization_id?: string
          parent_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_nodes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_nodes_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "organization_nodes"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_units: {
        Row: {
          code: string
          created_at: string
          id: string
          name: string
          organization_id: string
          organization_node_id: string
          status: string
          unit_type: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          name: string
          organization_id: string
          organization_node_id: string
          status?: string
          unit_type: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          organization_node_id?: string
          status?: string
          unit_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_units_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_units_organization_node_id_fkey"
            columns: ["organization_node_id"]
            isOneToOne: false
            referencedRelation: "organization_nodes"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          code: string
          created_at: string
          id: string
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      permissions: {
        Row: {
          code: string
          created_at: string
          description: string | null
          domain: string
          id: string
          is_privileged: boolean
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          domain: string
          id?: string
          is_privileged?: boolean
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          domain?: string
          id?: string
          is_privileged?: boolean
        }
        Relationships: []
      }
      profiles: {
        Row: {
          auth_user_id: string
          created_at: string
          full_name: string | null
          id: string
          organization_id: string | null
          phone: string | null
          status: string
          updated_at: string
        }
        Insert: {
          auth_user_id: string
          created_at?: string
          full_name?: string | null
          id?: string
          organization_id?: string | null
          phone?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          auth_user_id?: string
          created_at?: string
          full_name?: string | null
          id?: string
          organization_id?: string | null
          phone?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      regulatory_authorizations: {
        Row: {
          authorization_number: string | null
          authorization_type: string
          created_at: string
          effective_date: string | null
          expiry_date: string | null
          id: string
          issuing_authority: string | null
          module_code: string
          notes: string | null
          organization_id: string
          organization_unit_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          authorization_number?: string | null
          authorization_type: string
          created_at?: string
          effective_date?: string | null
          expiry_date?: string | null
          id?: string
          issuing_authority?: string | null
          module_code: string
          notes?: string | null
          organization_id: string
          organization_unit_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          authorization_number?: string | null
          authorization_type?: string
          created_at?: string
          effective_date?: string | null
          expiry_date?: string | null
          id?: string
          issuing_authority?: string | null
          module_code?: string
          notes?: string | null
          organization_id?: string
          organization_unit_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "regulatory_authorizations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "regulatory_authorizations_organization_unit_id_fkey"
            columns: ["organization_unit_id"]
            isOneToOne: false
            referencedRelation: "organization_units"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
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
            foreignKeyName: "role_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_privileged: boolean
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_privileged?: boolean
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_privileged?: boolean
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      user_permissions: {
        Row: {
          assigned_by: string | null
          created_at: string
          effect: string
          id: string
          permission_id: string
          profile_id: string
          reason: string | null
          valid_from: string
          valid_until: string | null
        }
        Insert: {
          assigned_by?: string | null
          created_at?: string
          effect: string
          id?: string
          permission_id: string
          profile_id: string
          reason?: string | null
          valid_from?: string
          valid_until?: string | null
        }
        Update: {
          assigned_by?: string | null
          created_at?: string
          effect?: string
          id?: string
          permission_id?: string
          profile_id?: string
          reason?: string | null
          valid_from?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_permissions_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_permissions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          assigned_by: string | null
          created_at: string
          id: string
          profile_id: string
          role_id: string
          valid_from: string
          valid_until: string | null
        }
        Insert: {
          assigned_by?: string | null
          created_at?: string
          id?: string
          profile_id: string
          role_id: string
          valid_from?: string
          valid_until?: string | null
        }
        Update: {
          assigned_by?: string | null
          created_at?: string
          id?: string
          profile_id?: string
          role_id?: string
          valid_from?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_roles_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_scope_assignments: {
        Row: {
          assigned_by: string | null
          created_at: string
          data_scope_id: string
          id: string
          profile_id: string
          valid_from: string
          valid_until: string | null
        }
        Insert: {
          assigned_by?: string | null
          created_at?: string
          data_scope_id: string
          id?: string
          profile_id: string
          valid_from?: string
          valid_until?: string | null
        }
        Update: {
          assigned_by?: string | null
          created_at?: string
          data_scope_id?: string
          id?: string
          profile_id?: string
          valid_from?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_scope_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_scope_assignments_data_scope_id_fkey"
            columns: ["data_scope_id"]
            isOneToOne: false
            referencedRelation: "data_scopes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_scope_assignments_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      has_permission: {
        Args: { p_permission_code: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

export type Tables<
  TableName extends keyof Database["public"]["Tables"],
> = Database["public"]["Tables"][TableName]["Row"]

export type TablesInsert<
  TableName extends keyof Database["public"]["Tables"],
> = Database["public"]["Tables"][TableName]["Insert"]

export type TablesUpdate<
  TableName extends keyof Database["public"]["Tables"],
> = Database["public"]["Tables"][TableName]["Update"]
