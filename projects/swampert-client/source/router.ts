import { createWebHistory, createRouter } from "vue-router";

import { useAuthStore } from "@features/auth/auth.store";

const history = createWebHistory(import.meta.env.BASE_URL);

export const router = createRouter({
  history,
  routes: [
    {
      path: "/login",
      name: "login",
      component: () => import("@features/auth/LoginView.vue"),
    },
    {
      path: "/dashboard",
      component: () => import("@shared/DashboardLayout.vue"),
      redirect: { name: "dashboard-kpis" },
      children: [
        { path: "kpis", name: "dashboard-kpis", component: () => import("@features/reports/KpisView.vue") },
        { path: "trends", name: "dashboard-trends", component: () => import("@features/reports/TrendsView.vue") },
        { path: "detail", name: "dashboard-detail", component: () => import("@features/reports/DetailView.vue") },
      ],
    },
    { path: "/", redirect: { name: "dashboard-kpis" } },
  ],
});

// Protege todo /dashboard/*; /login es la única ruta pública —
// deltas/analytics-dashboard.spec.md § Criterios de aceptación.
router.beforeEach((to) => {
  const auth = useAuthStore();

  if (to.name !== "login" && !auth.isAuthenticated) {
    return { name: "login" };
  }

  if (to.name === "login" && auth.isAuthenticated) {
    return { name: "dashboard-kpis" };
  }
});
