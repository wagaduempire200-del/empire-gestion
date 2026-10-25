/**
 * EMPIRE GESTION — Cloudflare Worker API starter
 * Bind a Cloudflare D1 database with binding name: DB
 *
 * This API is a backend foundation. It does NOT yet make the existing v3.0
 * HTML use the server database; the HTML must be adapted and tested separately.
 */
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders },
  });
}
function bad(message, status = 400) { return json({ ok: false, error: message }, status); }
async function bodyJson(request) {
  try { return await request.json(); } catch { return null; }
}
function positiveNumber(v, label, allowZero = false) {
  const n = Number(v);
  if (!Number.isFinite(n) || (allowZero ? n < 0 : n <= 0)) throw new Error(`${label} invalide`);
  return n;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (!env.DB) {
      return bad("La liaison D1 « DB » n'est pas configurée sur ce Worker.", 500);
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    const method = request.method.toUpperCase();

    try {
      if (path === "/" || path === "/api/health") {
        const db = await env.DB.prepare("SELECT 1 AS connected").first();
        return json({
          ok: true,
          service: "EMPIRE GESTION API",
          database: db?.connected === 1 ? "connected" : "unknown",
          note: "API de base. Le site HTML doit encore être adapté pour utiliser cette API."
        });
      }

      if (path === "/api/units" && method === "GET") {
        const { results } = await env.DB.prepare(
          "SELECT id, name FROM business_units ORDER BY id"
        ).all();
        return json({ ok: true, data: results });
      }

      // Products
      if (path === "/api/products" && method === "GET") {
        const unitId = Number(url.searchParams.get("unit_id"));
        if (!Number.isInteger(unitId) || unitId < 1) return bad("unit_id est obligatoire.");
        const { results } = await env.DB.prepare(
          "SELECT id, unit_id, sku, name, description, unit_of_measure, purchase_price, sale_price, currency_code, active, created_at FROM products WHERE unit_id = ? AND active = 1 ORDER BY id DESC"
        ).bind(unitId).all();
        return json({ ok: true, data: results });
      }
      if (path === "/api/products" && method === "POST") {
        const b = await bodyJson(request);
        if (!b || !Number.isInteger(Number(b.unit_id)) || Number(b.unit_id) < 1 || !String(b.name || "").trim()) return bad("unit_id et name sont obligatoires.");
        const purchase = positiveNumber(b.purchase_price ?? 0, "purchase_price", true);
        const sale = positiveNumber(b.sale_price ?? 0, "sale_price", true);
        const result = await env.DB.prepare(
          "INSERT INTO products (unit_id, sku, name, description, unit_of_measure, purchase_price, sale_price, currency_code, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)"
        ).bind(
          Number(b.unit_id), String(b.sku || "").trim() || null,
          String(b.name).trim(), String(b.description || "").trim() || null,
          String(b.unit_of_measure || "pièce"), purchase, sale,
          String(b.currency_code || "XOF")
        ).run();
        return json({ ok: true, id: result.meta.last_row_id }, 201);
      }

      // Clients and suppliers (parties)
      if (path === "/api/parties" && method === "GET") {
        const type = url.searchParams.get("party_type");
        if (!["CLIENT", "SUPPLIER"].includes(type)) return bad("party_type doit être CLIENT ou SUPPLIER.");
        const { results } = await env.DB.prepare(
          "SELECT id, party_type, name, phone, email, address, country, tax_number, notes, active, created_at FROM parties WHERE party_type = ? AND active = 1 ORDER BY id DESC"
        ).bind(type).all();
        return json({ ok: true, data: results });
      }
      if (path === "/api/parties" && method === "POST") {
        const b = await bodyJson(request);
        if (!b || !["CLIENT", "SUPPLIER"].includes(b.party_type) || !String(b.name || "").trim()) return bad("party_type et name sont obligatoires.");
        const result = await env.DB.prepare(
          "INSERT INTO parties (party_type, name, phone, email, address, country, tax_number, notes, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)"
        ).bind(
          b.party_type, String(b.name).trim(), String(b.phone || "").trim() || null,
          String(b.email || "").trim() || null, String(b.address || "").trim() || null,
          String(b.country || "Mali"), String(b.tax_number || "").trim() || null,
          String(b.notes || "").trim() || null
        ).run();
        return json({ ok: true, id: result.meta.last_row_id }, 201);
      }

      // Transactions + lines. This endpoint records a header only; use transaction-items
      // endpoint for lines, and do not use for official accounting before full validation.
      if (path === "/api/transactions" && method === "GET") {
        const unitId = Number(url.searchParams.get("unit_id"));
        if (!Number.isInteger(unitId) || unitId < 1) return bad("unit_id est obligatoire.");
        const { results } = await env.DB.prepare(
          "SELECT id, unit_id, party_id, transaction_type, reference, transaction_date, status, currency_code, subtotal, total_amount, notes, created_by FROM transactions WHERE unit_id = ? ORDER BY id DESC LIMIT 200"
        ).bind(unitId).all();
        return json({ ok: true, data: results });
      }
      if (path === "/api/transactions" && method === "POST") {
        const b = await bodyJson(request);
        if (!b || !Number.isInteger(Number(b.unit_id)) || Number(b.unit_id) < 1 || !["SALE", "PURCHASE", "EXPENSE", "ADJUSTMENT"].includes(b.transaction_type)) return bad("unit_id et transaction_type valide sont obligatoires.");
        const total = positiveNumber(b.total_amount ?? 0, "total_amount", true);
        const subtotal = positiveNumber(b.subtotal ?? total, "subtotal", true);
        const result = await env.DB.prepare(
          "INSERT INTO transactions (unit_id, party_id, transaction_type, reference, transaction_date, status, currency_code, subtotal, total_amount, notes, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ).bind(
          Number(b.unit_id), b.party_id ? Number(b.party_id) : null,
          b.transaction_type, String(b.reference || "").trim() || null,
          String(b.transaction_date || new Date().toISOString().slice(0, 10)),
          String(b.status || "RECORDED"), String(b.currency_code || "XOF"),
          subtotal, total, String(b.notes || "").trim() || null,
          b.created_by ? String(b.created_by) : null
        ).run();
        return json({ ok: true, id: result.meta.last_row_id }, 201);
      }

      // Transaction line
      if (path === "/api/transaction-items" && method === "POST") {
        const b = await bodyJson(request);
        if (!b || !Number(b.transaction_id) || !Number(b.product_id)) return bad("transaction_id et product_id sont obligatoires.");
        const qty = positiveNumber(b.quantity, "quantity");
        const price = positiveNumber(b.unit_price ?? 0, "unit_price", true);
        const discount = positiveNumber(b.discount ?? 0, "discount", true);
        const lineTotal = Math.max(0, qty * price - discount);
        const result = await env.DB.prepare(
          "INSERT INTO transaction_items (transaction_id, product_id, quantity, unit_price, discount, line_total) VALUES (?, ?, ?, ?, ?, ?)"
        ).bind(Number(b.transaction_id), Number(b.product_id), qty, price, discount, lineTotal).run();
        return json({ ok: true, id: result.meta.last_row_id, line_total: lineTotal }, 201);
      }

      // Payments
      if (path === "/api/payments" && method === "GET") {
        const transactionId = Number(url.searchParams.get("transaction_id"));
        if (!Number.isInteger(transactionId) || transactionId < 1) return bad("transaction_id est obligatoire.");
        const { results } = await env.DB.prepare(
          "SELECT id, transaction_id, amount, currency_code, payment_method, payment_date, reference, notes, received_by FROM payments WHERE transaction_id = ? ORDER BY id DESC"
        ).bind(transactionId).all();
        return json({ ok: true, data: results });
      }
      if (path === "/api/payments" && method === "POST") {
        const b = await bodyJson(request);
        if (!b || !Number(b.transaction_id)) return bad("transaction_id est obligatoire.");
        const amount = positiveNumber(b.amount, "amount");
        const result = await env.DB.prepare(
          "INSERT INTO payments (transaction_id, amount, currency_code, payment_method, payment_date, reference, notes, received_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        ).bind(
          Number(b.transaction_id), amount, String(b.currency_code || "XOF"),
          String(b.payment_method || "CASH"),
          String(b.payment_date || new Date().toISOString().slice(0, 10)),
          String(b.reference || "").trim() || null,
          String(b.notes || "").trim() || null, b.received_by ? String(b.received_by) : null
        ).run();
        return json({ ok: true, id: result.meta.last_row_id }, 201);
      }

      // Stock movements
      if (path === "/api/stock-movements" && method === "GET") {
        const unitId = Number(url.searchParams.get("unit_id"));
        if (!Number.isInteger(unitId) || unitId < 1) return bad("unit_id est obligatoire.");
        const { results } = await env.DB.prepare(
          "SELECT id, unit_id, product_id, movement_type, quantity, reference, notes, movement_date, created_by FROM stock_movements WHERE unit_id = ? ORDER BY id DESC LIMIT 200"
        ).bind(unitId).all();
        return json({ ok: true, data: results });
      }
      if (path === "/api/stock-movements" && method === "POST") {
        const b = await bodyJson(request);
        if (!b || !Number(b.unit_id) || !Number(b.product_id) || !String(b.movement_type || "").trim()) return bad("unit_id, product_id et movement_type sont obligatoires.");
        const qty = positiveNumber(b.quantity, "quantity");
        const result = await env.DB.prepare(
          "INSERT INTO stock_movements (unit_id, product_id, movement_type, quantity, reference, notes, movement_date, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        ).bind(
          Number(b.unit_id), Number(b.product_id), String(b.movement_type),
          qty, String(b.reference || "").trim() || null,
          String(b.notes || "").trim() || null,
          String(b.movement_date || new Date().toISOString().slice(0, 10)),
          b.created_by ? String(b.created_by) : null
        ).run();
        return json({ ok: true, id: result.meta.last_row_id }, 201);
      }

      return bad("Route API inconnue.", 404);
    } catch (error) {
      return bad(error?.message || "Erreur interne.", 500);
    }
  },
};
