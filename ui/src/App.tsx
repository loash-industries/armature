import { useState, useEffect } from 'react'
import './App.css'

function App() {
  const [message, setMessage] = useState<string>('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/')
      .then((res) => res.text())
      .then((data) => {
        setMessage(data)
        setLoading(false)
      })
      .catch((err) => {
        setMessage('Failed to connect to API')
        setLoading(false)
        console.error(err)
      })
  }, [])

  return (
    <div className="app">
      <h1>Test UI</h1>
      <div className="card">
        <h2>API Response:</h2>
        {loading ? <p>Loading...</p> : <p>{message}</p>}
      </div>
    </div>
  )
}

export default App
