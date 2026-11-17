// 门户网站：www.quotlet.com 永久跳转到 quotlet.com，其余请求交给静态文件
export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (url.hostname.startsWith('www.')) {
      url.hostname = url.hostname.slice(4)
      return Response.redirect(url.toString(), 301)
    }
    return env.ASSETS.fetch(request)
  },
}
