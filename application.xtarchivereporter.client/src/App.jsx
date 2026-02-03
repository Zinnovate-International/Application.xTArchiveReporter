import { useState } from 'react'
import './App.css'

const initialFilters = {
    fromObjPath: '',
    contractObjPath: '',
    toObjPath: '',
    startDate: '',
    endDate: '',
}

function App() {
    const [filters, setFilters] = useState(initialFilters)
    const [results, setResults] = useState([])
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState('')
    const [exporting, setExporting] = useState(false)

    const formatPath = (value) => {
        if (!value) {
            return '--'
        }

        const prefixes = [
            'xt-node:/NXS_NipponExpress/',
            'xt-contract:/NXS_NipponExpress/',
            'xt-node:/',
            'xt-contract:/'
        ]

        for (const prefix of prefixes) {
            if (value.startsWith(prefix)) {
                return value.slice(prefix.length)
            }
        }

        return value
    }

    const normalizeDateValue = (value) => {
        if (!value) {
            return ''
        }

        const parsed = new Date(value)
        if (Number.isNaN(parsed)) {
            return value
        }

        return parsed.toISOString().slice(0, 10)
    }

    const buildErrorFromResponse = async (response) => {
        let details = ''
        try {
            const contentType = response.headers.get('content-type') || ''
            if (contentType.includes('application/json')) {
                const body = await response.json()
                details = typeof body === 'string' ? body : JSON.stringify(body)
            } else {
                details = await response.text()
            }
        } catch {
            // ignore parsing errors
        }

        const suffix = details?.trim() ? ` - ${details.trim()}` : ''
        return `HTTP ${response.status} ${response.statusText}${suffix}`
    }

    const handleInputChange = (field) => (event) => {
        const { value } = event.target
        const nextValue = field === 'startDate' || field === 'endDate' ? normalizeDateValue(value) : value
        setFilters((prev) => ({ ...prev, [field]: nextValue }))
    }

    const resetFilters = () => {
        setFilters(initialFilters)
    }

    const buildSearchParams = () => {
        const searchParams = new URLSearchParams()
        Object.entries(filters).forEach(([key, value]) => {
            if (value) {
                const sanitized = key === 'startDate' || key === 'endDate' ? normalizeDateValue(value) : value
                searchParams.append(key, sanitized)
            }
        })

        return searchParams
    }

    const handleSubmit = async (event) => {
        event.preventDefault()
        setLoading(true)
        setError('')

        try {
            const searchParams = buildSearchParams()
            const url = searchParams.toString()
                ? `/api/metainfaggregations?${searchParams.toString()}`
                : '/api/metainfaggregations'

            const response = await fetch(url)
            if (!response.ok) {
                throw new Error(await buildErrorFromResponse(response))
            }

            const data = await response.json()
            setResults(data)
        } catch (fetchError) {
            setError(fetchError.message)
            setResults([])
        } finally {
            setLoading(false)
        }
    }

    const handleExport = async () => {
        setExporting(true)
        setError('')

        try {
            const searchParams = buildSearchParams()
            const url = searchParams.toString()
                ? `/api/metainfaggregations/export?${searchParams.toString()}`
                : '/api/metainfaggregations/export'

            const response = await fetch(url)
            if (!response.ok) {
                throw new Error(await buildErrorFromResponse(response))
            }

            const blob = await response.blob()
            let fileName = 'metainf-aggregations.xlsx'
            const contentDisposition = response.headers.get('Content-Disposition')
            if (contentDisposition) {
                const match = /filename="?([^";]+)"?/i.exec(contentDisposition)
                if (match?.[1]) {
                    fileName = match[1]
                }
            }

            const urlObject = window.URL.createObjectURL(blob)
            const link = document.createElement('a')
            link.href = urlObject
            link.download = fileName
            document.body.appendChild(link)
            link.click()
            link.remove()
            window.URL.revokeObjectURL(urlObject)
        } catch (exportError) {
            setError(exportError.message)
        } finally {
            setExporting(false)
        }
    }

    const hasResults = results.length > 0

    return (
        <div className="container-fluid min-vh-100 py-4 metainf-layout">
            <div className="row g-4 h-100">
                <div className="col-12 col-lg-3 col-xl-3 metainf-sidebar">
                    <div className="card h-100 shadow-sm">
                        <div className="card-body d-flex flex-column">
                            <div className="w-100 bg-primary py-4">
                                <div className="filter-logo text-center">
                                    <img src="https://zinnovate.se/wp-content/uploads/2025/10/zinnovate-web-logo-400x85.png" alt="Zinnovate logo" className="img-fluid" />
                                </div>
                            </div>
                            <hr />
                            <div className="d-flex justify-content-between align-items-center mb-3">
                                <div>
                                    <h1 className="h5 mb-1">Metainf Filters</h1>
                                    <p className="text-muted mb-0">All filters use case-insensitive LIKE matching.</p>
                                </div>
                            </div>

                            <form className="d-flex flex-column flex-grow-1" onSubmit={handleSubmit}>
                                <div className="mb-3">
                                    <label className="form-label" htmlFor="fromObjPath">From object path</label>
                                    <input
                                        id="fromObjPath"
                                        className="form-control"
                                        placeholder="e.g. NX-DB"
                                        value={filters.fromObjPath}
                                        onChange={handleInputChange('fromObjPath')}
                                    />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label" htmlFor="contractObjPath">Contract object path</label>
                                    <input
                                        id="contractObjPath"
                                        className="form-control"
                                        placeholder="Contract path"
                                        value={filters.contractObjPath}
                                        onChange={handleInputChange('contractObjPath')}
                                    />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label" htmlFor="toObjPath">To object path</label>
                                    <input
                                        id="toObjPath"
                                        className="form-control"
                                        placeholder="Receiver path"
                                        value={filters.toObjPath}
                                        onChange={handleInputChange('toObjPath')}
                                    />
                                </div>
                                <div className="row g-3">
                                    <div className="col-12 col-sm-6">
                                        <label className="form-label" htmlFor="startDate">Start date</label>
                                        <input
                                            id="startDate"
                                            type="text"
                                            inputMode="numeric"
                                            pattern="\d{4}-\d{2}-\d{2}"
                                            className="form-control"
                                            placeholder="yyyy-mm-dd"
                                            value={filters.startDate}
                                            onChange={handleInputChange('startDate')}
                                        />
                                    </div>
                                    <div className="col-12 col-sm-6">
                                        <label className="form-label" htmlFor="endDate">End date</label>
                                        <input
                                            id="endDate"
                                            type="text"
                                            inputMode="numeric"
                                            pattern="\d{4}-\d{2}-\d{2}"
                                            className="form-control"
                                            placeholder="yyyy-mm-dd"
                                            value={filters.endDate}
                                            onChange={handleInputChange('endDate')}
                                        />
                                    </div>
                                </div>
                                <div className="mt-auto pt-4 d-flex gap-2 flex-wrap">
                                    <button
                                        type="button"
                                        className="btn btn-outline-secondary flex-fill"
                                        onClick={resetFilters}
                                        disabled={loading || exporting}
                                    >
                                        Reset
                                    </button>
                                    <button
                                        type="submit"
                                        className="btn btn-primary flex-fill d-flex align-items-center justify-content-center gap-2"
                                        disabled={loading || exporting}
                                    >
                                        {loading && <span className="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>}
                                        <span>Request data</span>
                                    </button>
                                    <button
                                        type="button"
                                        className="btn btn-secondary flex-fill d-flex align-items-center justify-content-center gap-2"
                                        onClick={handleExport}
                                        disabled={exporting || loading}
                                    >
                                        {exporting && <span className="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>}
                                        <span>Export to Excel</span>
                                    </button>
                                </div>
                            </form>
                        </div>
                    </div>
                </div>
                <div className="col-12 col-lg-9 col-xl-9">
                    <div className="card h-100 shadow-sm">
                        <div className="card-body d-flex flex-column h-100">
                            <div className="d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2">
                                <h2 className="h5 mb-0">Aggregated incidents</h2>
                                <span className="text-muted small">{results.length} rows</span>
                            </div>
                            {error && (
                                <div className="alert alert-danger" role="alert">
                                    {error}
                                </div>
                            )}
                            <div className="metainf-table-wrapper table-responsive flex-grow-1">
                                {loading && (
                                    <div className="table-loading-overlay" role="status" aria-live="polite">
                                        <div className="spinner-border text-primary" role="status" aria-hidden="true"></div>
                                        <p className="mt-2 mb-0 fw-semibold">Fetching data...</p>
                                    </div>
                                )}
                                <table className={`table table-sm table-striped align-middle ${loading ? 'opacity-50' : ''}`} aria-busy={loading}>
                                    <thead className="table-light position-sticky top-0">
                                        <tr>
                                            <th scope="col">From path</th>
                                            <th scope="col">Contract path</th>
                                            <th scope="col">To path</th>
                                            <th scope="col" className="text-end">Incidents</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {hasResults ? (
                                            results.map((row, index) => (
                                                <tr key={`${row.fromObjPath}-${row.contractObjPath}-${row.toObjPath}-${index}`}>
                                                    <td className="text-break">{formatPath(row.fromObjPath)}</td>
                                                    <td className="text-break">{formatPath(row.contractObjPath)}</td>
                                                    <td className="text-break">{formatPath(row.toObjPath)}</td>
                                                    <td className="text-end fw-semibold">{row.incidentCount}</td>
                                                </tr>
                                            ))
                                        ) : (
                                            <tr>
                                                <td colSpan="4" className="text-center py-5 text-muted">
                                                    {loading ? 'Fetching data…' : 'No results to display. Use the filters to request data.'}
                                                </td>
                                            </tr>
                                        )}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    )
}

export default App
