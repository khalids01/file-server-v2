export const Clipboard = {
  mounted() {
    this.copy = async () => {
      const status = this.el.querySelector('[role="status"]')
      const path = this.el.dataset.downloadPath
      try {
        if (!/^\/files\/[0-9a-f-]{36}\/download$/i.test(path || "")) throw new Error("Invalid private link")
        await navigator.clipboard.writeText(new URL(path, window.location.origin).href)
        status.textContent = "Copied · sign-in required"
      } catch {
        status.textContent = "Could not copy. Use the Download button."
      }
    }
    this.el.addEventListener("click", this.copy)
  },
  destroyed() { this.el.removeEventListener("click", this.copy) },
}
