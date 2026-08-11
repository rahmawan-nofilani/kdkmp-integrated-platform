"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asFinancialProductClient } from "@/types/financial-products";

function errorCode(message: string) {
  if (message.includes("FINANCIAL_PRODUCT_CODE_ALREADY_EXISTS")) return "duplicate-code";
  if (message.includes("FINANCIAL_PRODUCT_TEMPLATE_INVALID")) return "invalid-template";
  if (message.includes("SAVINGS_LOANS_UNIT_REQUIRED")) return "unit-required";
  if (message.includes("INVALID_SAVINGS_LOANS_UNIT")) return "invalid-unit";
  if (message.includes("FINANCIAL_PRODUCT_SCOPE_DENIED")) return "scope-denied";
  if (message.includes("FINANCIAL_PRODUCT_IDENTITY_REQUIRED")) return "missing-identity";
  return "system";
}

export async function createFinancialProductDraftAction(formData: FormData) {
  await requirePermission("FINANCIAL_PRODUCT_CREATE");

  const templateCode = String(formData.get("template_code") ?? "").trim();
  const productCode = String(formData.get("product_code") ?? "").trim();
  const productName = String(formData.get("product_name") ?? "").trim();
  const legalProductType = String(formData.get("legal_product_type") ?? "").trim();
  const purposeCode = String(formData.get("purpose_code") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();

  if (!templateCode || !productCode || !productName) {
    redirect("/dashboard/financial-products?error=missing-identity");
  }

  const { supabase } = await requireAccessContext();
  const db = asFinancialProductClient(supabase);
  const { error } = await db.rpc("create_financial_product_draft", {
    p_template_code: templateCode,
    p_product_code: productCode,
    p_product_name: productName,
    p_legal_product_type: legalProductType || undefined,
    p_purpose_code: purposeCode || undefined,
    p_description: description || undefined,
  });

  if (error) {
    redirect(`/dashboard/financial-products?error=${errorCode(error.message)}`);
  }

  revalidatePath("/dashboard/financial-products");
  redirect("/dashboard/financial-products?success=created");
}
