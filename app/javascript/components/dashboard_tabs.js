const showTab = (tabId) => {
  const tabContents = document.querySelectorAll(".tabs-container .tab-content")
  tabContents.forEach((tabContent) => {
    tabContent.classList.add("d-none")
  })
  const tabContent = document.querySelector(`[data-tab-content-id=${tabId}]`)
  tabContent.classList.remove("d-none")
}
const initDashboardTabs = () => {
  const tabs = document.querySelectorAll(".tabs-container .tabs input[name=tabs]")
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const tabId = tab.dataset.tabContent
      showTab(tabId)
    })
  })
}
export { initDashboardTabs }
