// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;

namespace IdentityServer.AdminPortal.Server.Controllers;

[ApiController]
[Authorize(Policy = Constants.PolicyNames.RequireUserRole)]
[Produces("application/json")]
public abstract class BasePropertyController<TRead, TCreate> : ControllerBase
    where TRead : IDtoRead
    where TCreate : IDtoCreate
{
    private readonly IDtoCreateRepository<TRead, TCreate> _propertyRepository;

    protected BasePropertyController(IDtoCreateRepository<TRead, TCreate> propertyRepository)
    {
        _propertyRepository = propertyRepository;
    }

    [HttpPost]
    public async Task<ActionResult<TRead>> CreatePropertyAsync([FromBody] TCreate item)
    {
        // Validate the model using DataAnnotations
        var validationResults = new List<ValidationResult>();
        var validationContext = new ValidationContext(item);

        if (!Validator.TryValidateObject(item, validationContext, validationResults, validateAllProperties: true))
        {
            // If validation fails, return a 400 Bad Request with validation errors
            return BadRequest(validationResults);
        }

        // Proceed with creating the resource if validation passes
        var addedResource = await _propertyRepository.CreateAsync(User, item);
        return Ok(addedResource);
    }

    [HttpDelete("{id:int}")]
    public async Task<ActionResult<int>> DeletePropertyByIdAsync(int id)
    {
        int? deletedItem = await _propertyRepository.DeleteAsync(User, id);

        return deletedItem == null
            ? NotFound()
            : Ok(deletedItem);
    }
}
