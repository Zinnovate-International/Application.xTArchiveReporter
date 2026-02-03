using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Swedwise.NodiniteXTArchiveManager.Models;

namespace Application.xTArchiveReporter.Server.Controllers;

[ApiController]
[Route("api/[controller]")]
public class MetainfAggregationsController : ControllerBase
{
    private readonly MetainfDbContext _context;

    public MetainfAggregationsController(MetainfDbContext context)
    {
        _context = context;
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<MetainfAggregationResult>>> GetAggregations(
        [FromQuery] MetainfAggregationRequest request,
        CancellationToken cancellationToken)
    {
        var validationMessage = ValidateRequest(request);
        if (validationMessage is not null)
        {
            return BadRequest(validationMessage);
        }

        var aggregations = await ProjectAggregations(BuildFilteredQuery(request))
            .ToListAsync(cancellationToken);

        return Ok(aggregations);
    }

    [HttpGet("export")]
    public async Task<IActionResult> ExportAggregations(
        [FromQuery] MetainfAggregationRequest request,
        CancellationToken cancellationToken)
    {
        var validationMessage = ValidateRequest(request);
        if (validationMessage is not null)
        {
            return BadRequest(validationMessage);
        }

        var aggregations = await ProjectAggregations(BuildFilteredQuery(request))
            .ToListAsync(cancellationToken);

        using var workbook = new XLWorkbook();
        var worksheet = workbook.Worksheets.Add("Aggregations");

        var generatedAt = DateTime.UtcNow;
        var row = 1;
        worksheet.Cell(row, 1).Value = "Metainf Aggregations Export";
        worksheet.Range(row, 1, row, 4).Merge();
        worksheet.Cell(row, 1).Style.Font.SetBold();
        row += 2;

        worksheet.Cell(row, 1).Value = "Generated (UTC)";
        worksheet.Cell(row, 2).Value = generatedAt.ToString("u");
        row++;

        foreach (var (label, value) in GetFilterSummary(request))
        {
            worksheet.Cell(row, 1).Value = label;
            worksheet.Cell(row, 2).Value = string.IsNullOrWhiteSpace(value) ? "—" : value;
            row++;
        }

        row++;
        var headerRow = row;
        worksheet.Cell(headerRow, 1).Value = "From path";
        worksheet.Cell(headerRow, 2).Value = "Contract path";
        worksheet.Cell(headerRow, 3).Value = "To path";
        worksheet.Cell(headerRow, 4).Value = "Incidents";
        worksheet.Range(headerRow, 1, headerRow, 4).Style.Font.SetBold();

        foreach (var aggregation in aggregations)
        {
            row++;
            worksheet.Cell(row, 1).Value = aggregation.FromObjPath;
            worksheet.Cell(row, 2).Value = aggregation.ContractObjPath;
            worksheet.Cell(row, 3).Value = aggregation.ToObjPath;
            worksheet.Cell(row, 4).Value = aggregation.IncidentCount;
        }

        worksheet.Columns().AdjustToContents();

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        var content = stream.ToArray();
        var fileName = $"metainf-aggregations-{generatedAt:yyyyMMddHHmmss}.xlsx";
        return File(content, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName);
    }

    private IQueryable<MetainfFileEntity> BuildFilteredQuery(MetainfAggregationRequest request)
    {
        IQueryable<MetainfFileEntity> query = _context.Metainfs.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(request.FromObjPath))
        {
            if (IsNoneToken(request.FromObjPath))
            {
                query = query.Where(m => string.IsNullOrEmpty(m.FromObjPath));
            }
            else
            {
                var pattern = BuildLikePattern(request.FromObjPath);
                query = query.Where(m => EF.Functions.Like(m.FromObjPath.ToLower(), pattern));
            }
        }

        if (!string.IsNullOrWhiteSpace(request.ContractObjPath))
        {
            if (IsNoneToken(request.ContractObjPath))
            {
                query = query.Where(m => string.IsNullOrEmpty(m.ContractObjPath));
            }
            else
            {
                var pattern = BuildLikePattern(request.ContractObjPath);
                query = query.Where(m => EF.Functions.Like(m.ContractObjPath.ToLower(), pattern));
            }
        }

        if (!string.IsNullOrWhiteSpace(request.ToObjPath))
        {
            if (IsNoneToken(request.ToObjPath))
            {
                query = query.Where(m => string.IsNullOrEmpty(m.ToObjPath));
            }
            else
            {
                var pattern = BuildLikePattern(request.ToObjPath);
                query = query.Where(m => EF.Functions.Like(m.ToObjPath.ToLower(), pattern));
            }
        }

        if (request.StartDate is not null)
        {
            query = query.Where(m => m.CreationTimeDt >= request.StartDate.Value);
        }

        if (request.EndDate is not null)
        {
            query = query.Where(m => m.CreationTimeDt <= request.EndDate.Value);
        }

        return query;
    }

    private static IQueryable<MetainfAggregationResult> ProjectAggregations(IQueryable<MetainfFileEntity> query)
    {
        return query
            .GroupBy(m => new { m.FromObjPath, m.ContractObjPath, m.ToObjPath })
            .Select(g => new MetainfAggregationResult
            {
                FromObjPath = g.Key.FromObjPath,
                ContractObjPath = g.Key.ContractObjPath,
                ToObjPath = g.Key.ToObjPath,
                IncidentCount = g.Count()
            })
            .OrderByDescending(r => r.IncidentCount);
    }

    private static IEnumerable<(string Label, string? Value)> GetFilterSummary(MetainfAggregationRequest request)
    {
        yield return ("From object path", request.FromObjPath);
        yield return ("Contract object path", request.ContractObjPath);
        yield return ("To object path", request.ToObjPath);
        yield return ("Start date", request.StartDate?.ToString("yyyy-MM-dd"));
        yield return ("End date", request.EndDate?.ToString("yyyy-MM-dd"));
    }

    private static string? ValidateRequest(MetainfAggregationRequest request)
    {
        if (request.StartDate is not null && request.EndDate is not null && request.StartDate > request.EndDate)
        {
            return "StartDate cannot be greater than EndDate.";
        }

        return null;
    }

    private static bool IsNoneToken(string? value)
    {
        return !string.IsNullOrWhiteSpace(value) && string.Equals(value.Trim(), "none", StringComparison.OrdinalIgnoreCase);
    }

    private static string BuildLikePattern(string value)
    {
        var trimmed = value.Trim().ToLowerInvariant();
        return $"%{trimmed}%";
    }
}
