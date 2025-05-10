# Ensure required packages are installed (uncomment if needed)
# using Pkg
# Pkg.add(["GLMakie", "CSV", "DataFrames", "Colors"])

# Load necessary libraries
using GLMakie
using CSV
using DataFrames
using Logging
using Colors
using Statistics
using ProgressMeter

# Configure Makie for better performance and rendering
GLMakie.activate!()

using DataFrames

function calculate_velocities(data::DataFrame)
    # Create new columns for velocity components and magnitude
    data[!, :VelX] = zeros(nrow(data))
    data[!, :VelY] = zeros(nrow(data))
    data[!, :VelZ] = zeros(nrow(data))
    data[!, :VelMagnitude] = zeros(nrow(data))
    
    # Group data by BodyID so we compute the differences per particle
    gdf = groupby(data, :BodyID)
    
    for subdf in gdf
        # Sort each subgroup by iteration to ensure correct ordering
        sort!(subdf, :Iteration)
        n = nrow(subdf)
        
        # Only compute differences if there are at least 2 iterations
        if n > 1
            # Compute differences in each coordinate for successive iterations
            vel_x = diff(subdf[!, :PosX])
            vel_y = diff(subdf[!, :PosY])
            vel_z = diff(subdf[!, :PosZ])
            
            # For iterations 2..n, assign the computed differences
            subdf[2:end, :VelX] = vel_x
            subdf[2:end, :VelY] = vel_y
            subdf[2:end, :VelZ] = vel_z
            
            # Compute the magnitude of the velocity vector
            subdf[2:end, :VelMagnitude] = sqrt.(vel_x.^2 .+ vel_y.^2 .+ vel_z.^2)
        end
    end
    return data
end

function calculate_precise_limits(data, iteration)
    iter_data = data[data.Iteration .== iteration, :]

    # Calculate centroid
    centroid_x = mean(iter_data.PosX)
    centroid_y = mean(iter_data.PosY)
    centroid_z = mean(iter_data.PosZ)


    # Calculate dispersion range
    x_range = maximum(iter_data.PosX) - minimum(iter_data.PosX)
    y_range = maximum(iter_data.PosY) - minimum(iter_data.PosY)
    z_range = maximum(iter_data.PosZ) - minimum(iter_data.PosZ)


    # Tighter zoom
    zoom_factor = 0.5  # You can adjust this value
    #~ xlims = (centroid_x - x_range * zoom_factor, centroid_x + x_range * zoom_factor)
    #~ ylims = (centroid_y - y_range * zoom_factor, centroid_y + y_range * zoom_factor)
    #~ zlims = (centroid_z - z_range * zoom_factor, centroid_z + z_range * zoom_factor)

    xlims = (-6,6)
    ylims = (-6,6)
    zlims = (-6,6)

    return xlims, ylims, zlims
end

# Render the particle simulation in 2D projections
function render_particle_projections(data_path, output_path; manual_zoom_range=nothing)
    @info "Loading simulation data"
    data = CSV.read(data_path, DataFrame)

    # Calculate velocities
    @info "Calculating particle velocities"
    data = calculate_velocities(data)

    # Calculate velocity statistics
    velocities = filter(!iszero, data.VelMagnitude)
    min_velocity = quantile(velocities, 0.05)
    max_velocity = quantile(velocities, 0.95)

    @info "Velocity range: $min_velocity to $max_velocity"

    # Set theme
    dark_latexfonts = merge(theme_latexfonts())
    set_theme!(dark_latexfonts)

    # Create figure with subplots for 3 projections
    fig = Figure(resolution = (1200, 400))

    ax_xy = Axis(fig[1, 1], xlabel = "X", ylabel = "Y", title = "XY Projection")
    ax_xz = Axis(fig[1, 2], xlabel = "X", ylabel = "Z", title = "XZ Projection")
    ax_yz = Axis(fig[1, 3], xlabel = "Y", ylabel = "Z", title = "YZ Projection")

    iterations = sort(unique(data.Iteration))
    total_iterations = length(iterations)

    # Progress meter
    p = Progress(total_iterations, desc="Rendering projections...", 
                 barglyphs=ProgressMeter.BarGlyphs("[=> ]"), 
                 barlen=50, 
                 color=:green)

    # Animation recording block
    record(fig, output_path, iterations; framerate = 60) do iteration
        # Clear previous data
        empty!(ax_xy)
        empty!(ax_xz)
        empty!(ax_yz)

        # Precise zoom limits
        if isnothing(manual_zoom_range)
            xlims, ylims, zlims = calculate_precise_limits(data, iteration)
        else
            xlims, ylims, zlims = manual_zoom_range
        end
        limits!(ax, xlims[1], xlims[2], ylims[1], ylims[2], zlims[1], zlims[2])

        # Filter data for current iteration
        iter_data = data[data.Iteration .== iteration, :]

        # Prepare positions for each projection
        positions_xy = Point2f.(iter_data.PosX, iter_data.PosY)
        positions_xz = Point2f.(iter_data.PosX, iter_data.PosZ)
        positions_yz = Point2f.(iter_data.PosY, iter_data.PosZ)

        # Scatter plot for each projection with velocity-based coloration
        scatter!(ax_xy, positions_xy, 
            color = [RGBA(v/max_velocity, 0.2, 0.8, 0.8) for v in iter_data.VelMagnitude], 
            markersize = 8, 
            marker = :circle)

        scatter!(ax_xz, positions_xz, 
            color = [RGBA(v/max_velocity, 0.2, 0.8, 0.8) for v in iter_data.VelMagnitude], 
            markersize = 8, 
            marker = :circle)

        scatter!(ax_yz, positions_yz, 
            color = [RGBA(v/max_velocity, 0.2, 0.8, 0.8) for v in iter_data.VelMagnitude], 
            markersize = 8, 
            marker = :circle)
        next!(p)
    end
end

# Main execution
let
    data_path = "C:\\Users\\feder\\projects\\cuNBSim\\data\\simulation_data.csv"
    output_path = "leap_frog.mp4"
    render_particle_projections(data_path, output_path)
end

